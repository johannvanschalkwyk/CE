$mailboxes = Get-Mailbox | where {$_.ArchiveStatus -ne "None"}
foreach ($mailbox in $mailboxes) {
	$newarchivename = "In-Place Archive - "+$mailbox.DisplayName
	try {
		Set-Mailbox $mailbox.Alias -ArchiveName $newarchivename
		Write-Host "Archive mailbox name updated for $mailbox to {$newarchivename}" -ForegroundColor Green
	}
	catch {
		Write-Host "Archive mailbox name not successfully updated for $mailbox" -ForegroundColor Red
	}
}
