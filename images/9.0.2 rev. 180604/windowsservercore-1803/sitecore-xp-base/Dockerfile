# escape=`
FROM sitecore-base:9.0.180604-windowsservercore-1803

# Create certificates
RUN $env:CERT_PATH = 'C:\\certificates'; `
    $env:XCONNECT_CERT_NAME = 'xconnect-client'; `
    $env:XCONNECT_SSL_NAME = 'xconnect'; `
    $certPassword = (ConvertTo-SecureString -String 'Sp1JJvsrkXtWW9fOSFUh' -Force -AsPlainText); `
    New-Item -Path $env:CERT_PATH -ItemType Directory | Out-Null; `
    New-SelfSignedCertificate -CertStoreLocation 'cert:\localmachine\my' -DnsName $env:XCONNECT_CERT_NAME -KeyExportPolicy Exportable -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' | Export-PfxCertificate -FilePath ('{0}\\{1}.pfx' -f $env:CERT_PATH, $env:XCONNECT_CERT_NAME) -Password $certPassword; `
    New-SelfSignedCertificate -CertStoreLocation 'cert:\localmachine\my' -DnsName $env:XCONNECT_SSL_NAME -KeyExportPolicy Exportable -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' | Export-PfxCertificate -FilePath ('{0}\\{1}.pfx' -f $env:CERT_PATH, $env:XCONNECT_SSL_NAME) -Password $certPassword;
