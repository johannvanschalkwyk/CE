#Generate a random complex password with 15 characters
function Generate-ComplexPassword {
    $length = 15
    $lowercase = 'abcdefghijklmnopqrstuvwxyz'
    $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $numbers = '0123456789'
    $special = '!@#$%^&*()_+-=[]{}|;:,.<>?'

    $charset = "$lowercase$uppercase$numbers$special"
    
    $password = ""
    1..$length | ForEach-Object {
        $random = Get-Random -Maximum $charset.Length
        $password += $charset[$random]
    }

    return $password
}

Function WriteFile {
    Param (
        [string]$Data,
        [string]$Name
        )
    $Path = "C:\temp\Password Reset Logs\$FileDate-$Name.txt"
    Out-File -Append -FilePath $Path -Encoding default -InputObject $Data
}

$FileDate = Get-Date -Format "yyMMdd-HHmm"
$logpath = "C:\temp\Password Reset Logs\$FileDate-PassWordReset.txt"
$passworderrorcount = 0

#Get eBase users created with UnitySync
$users = Get-ADUser -Filter * -SearchBase "{OU}" -Properties adminDescription,whenCreated,extensionAttribute9,mail | Where {($_.adminDescription -eq "Created By UnitySync") -and ($_.extensionAttribute9 -ne "PW_Reset")} | Select SamAccountName,whenCreated,mail,UserPrincipalName
$ucount = $users.mail.count
If ($users -eq $null) {
    WriteFile -Data "COMPLETED: No new user accounts created requiring password reset." -Name PassWordReset
}
else {

    WriteFile -Data "COMPLETED: $ucount new user accounts needing password resets found." -Name PassWordReset
}

#Reset password and send email to user.
foreach ($user in $users) {
$upn = $user.UserPrincipalName
$sam = $user.sAMAccountName
$email = $user.mail
$ebasemail = $email.Replace("targetdomain.com","sourcedomain.com")

$passwordstring = Generate-ComplexPassword

#Reset the user's AD password with generated password
Try {
Set-ADAccountPassword -Identity $sam -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $passwordstring -Force)
WriteFile -Data "COMPLETED: Password reset for user $upn." -Name PassWordReset
}
Catch {
WriteFile -Data "ERROR: An error occured while attempting to reset the password for $upn - email not sent." -Name PassWordReset
$passworderrorcount ++
Continue
}

#Send an email to the user containing the password
#Define body of email message in HTMLformat
$body = @"
<html>
<head>
</head>
<body>
    <p>Dear User,</p>
    <p>Your account has been created. Notice that your access rights have to be created in another step. This will be done by the next day.</p>
    <p>Please try the first <u>login tomorrow after 12 pm</u>.</p>
    <p>Your account: $upn<br />
        Your starting password: $passwordstring</p>
    <p>Regards,<br />
       Your Integration Team</p>
    </body>
</html>
"@

#SMTP Credentials
$secpassword = ConvertTo-SecureString "Password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("smtpuser@domain.com",$secpassword)

#Execute Function to send email
Try{
Send-MailMessage -To $ebasemail -From "smtpuser@domain.com" -SmtpServer "smtpserver.domain.com" -Subject "Your Account" -Body $body -BodyAsHtml:$true -Credential $cred
WriteFile -Data "COMPLETED: Password emailed to user $ebasemail." -Name PassWordReset
}
Catch {
WriteFile -Data "ERROR: An error occured while attempting to email the password to $ebasemail." -Name PassWordReset
$passworderrorcount ++
Continue
}

#Update user password status attribute
Set-ADUser -Identity $sam -Replace @{extensionAttribute9 = "PW_Reset"}
}

WriteFile -Data "COMPLETED: Password reset script completed." -Name PasswordReset

#Send Password Reset Log File
$secpassword = ConvertTo-SecureString "Password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("smtpuser@domain.com",$secpassword)

If ($passworderrorcount -gt 0) {
    $logsubject = "Password Reset Script Completed With $passworderrorcount Errors"
}
else {
    $logsubject = "Password Reset Script Completed"
}
$logrecipients = @("recipient1@domain.com","recipient2@domain.com","johann.vanschalkwyk@cloudessentials.com")
Send-MailMessage -To $logrecipients -From "smtpuser@domain.com" -SmtpServer "smtpserver.domain.com" -Subject $logsubject -Body "See log file attached for more information." -BodyAsHtml:$true -Credential $cred -Attachments $logpath
