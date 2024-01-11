# Define the name of the issuer you are looking for
issuerName="" # - Include the name of the issuer as it shows in the certs you want to gather information on
ignoreLabel="" # - Include the label of a cert you don't want included (signing cert for a SCEP cert)

# Get the list of certificate labels issued by issuerName
issuerCertLabels=$(security find-certificate -a /Library/Keychains/System.keychain | awk -F'=' -v issuer="$issuerName" -v ignore="$ignoreLabel" '
  /"issu"/{issuerName = $0}
  /"labl"/{if (index(issuerName, issuer) > 0 && index($0, ignore) == 0) print $2}' | sed -e 's/^ *\"*//' -e 's/\"*$//')

# Convert the certificate labels to an array
certLabelsArray=($issuerCertLabels)

# Create an array of unique certs
uniqueCertLabelsArray=($(echo "${certLabelsArray[@]}" | tr ' ' '\n' | awk '!a[$0]++' | tr '\n' ' '))

# Calculate the number of original duplicates
originalNum=${#certLabelsArray[@]}
uniqueNum=${#uniqueCertLabelsArray[@]}
duplicatesNum=$((originalNum - uniqueNum))

# Create variables to store the script results
scriptResults=""
validCerts=""
invalidCerts=""
scriptResults+="Original count, including duplicates: $originalNum\n"
scriptResults+="Count of unique certificates: $uniqueNum\n"
scriptResults+="Number of duplicate certificates: $duplicatesNum\n"

# Check if issuerCertLabels is empty
if [[ -z "$issuerCertLabels" ]]; then
  scriptResults+="No certs were found\n"
else
    # Define a counter for valid certificates
    validCertCounter=0

    # Loop through each unique certificate label using for loop
    for certLabel in "${uniqueCertLabelsArray[@]}"
    do
        # Ignore if the label is the one to ignore
        if [[ "$certLabel" != "$ignoreLabel" ]]; then
            # Get the cert's PEM format data
            certificatePem=$(security find-certificate -a -p -c "$certLabel" /Library/Keychains/System.keychain)

            # Initialize empty string and array
            currentCertificate=""
            declare -a certificatesArray=()

            # Read each line in certificatePem
            while IFS= read -r line
            do
                # Add line to currentCertificate
                currentCertificate+="$line\n"
                
                # Check if line is end of a certificate
                if [[ $line == *"-----END CERTIFICATE-----"* ]]; then
                    # Add currentCertificate to array and clear currentCertificate
                    certificatesArray+=("$currentCertificate")
                    currentCertificate=""
                fi
            done <<< "$certificatePem"

            # Loop through each certificate in the certificatesArray
            for certificate in "${certificatesArray[@]}"
            do
                # Get the cert's validity dates
                notAfterDate=$(echo "$certificate" | openssl x509 -enddate -noout | cut -d= -f2)

                # Format the expiry date to a format that can be compared
                notAfterDateCompare=$(date -j -f "%b %d %T %Y %Z" "$notAfterDate" "+%s" 2>/dev/null)

                # Get the current date in a comparable format
                currentDateCompare=$(date "+%s")

                if [[ "$currentDateCompare" -lt "$notAfterDateCompare" ]]; then
                    validCerts+="VALID CERT: Certificate Label: $certLabel - Expire date: $notAfterDate\n"
                    validCertCounter=$((validCertCounter+1))
                else
                    invalidCerts+="INVALID CERT: Certificate Label: $certLabel - Certificate Expired on $notAfterDate\n"
                fi
            done


            
        fi
    done

    # Define a message if no valid certificates were found and concatenate the invalid certificates
    if [[ "$validCertCounter" -eq 0 ]]; then
        scriptResults+="No valid certificates found.\n"       
        scriptResults+="$invalidCerts"
    else
        scriptResults+="$validCerts"
    fi
    scriptResults+="Total valid certificates: $validCertCounter\n"
fi

echo -e "<result>$scriptResults</result>"