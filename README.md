# LanClipboard
A Powershell module for the FEX LAN Clipboard.

## Usage
Download [LanClipboard.psm1](LanClipboard.psm1) and install it to your Powershell environment using `Install-Module LanClipboard.psm1`.

The module exports the cmdlets `Set-LanClipboard` (`slcb`, `lcbput`) for storing data to the LAN clipboard, `Get-LanClipboard` (`glcb`, `lcbget`) for retrieving data and `Remove-LanClipboard` (`rlcb`, `rmlcb`, `lcbrm`). You can get detailed usage instructions by calling `Get-Help Set-LanClipboard -Full`, `Get-Help Get-LanClipboard -Full` and  `Get-Help Remove-LanClipboard -Full` respectively.
