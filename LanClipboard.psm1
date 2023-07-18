# Helper for making SDTP requests.
function Invoke-SdtpRequest {
    param(
        [string] $Server,
        [int] $Port,
        [string] $Path,
        [ValidateSet("GET", "PUT")] [string] $Method = "GET",
        [byte[]] $Body,
        [switch] $Raw
    )

    try {
        Write-Verbose "Connecting to $Server on port $Port ..."
        $connection = New-Object System.Net.Sockets.TcpClient($Server, $Port)
        $stream = $connection.GetStream();
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        Write-Verbose "$Method $($Path)"
        $writer.Write("$Method $($Path) SDTP/1.0`n`n")

        if ($Body) {
            Write-Verbose "Writing message body ..."
            $stream.Write($Body, 0, $Body.Length)
        }

        if ($Method -ieq "GET") {
            if ($Raw) {
                Write-Verbose "Reading binary response ..."
                $ms = New-Object System.IO.MemoryStream
                $stream.CopyTo($ms)
                $retval = $ms.ToArray();
                $msg = [System.Text.Encoding]::UTF8.GetString($retval)

                if ($msg -imatch "^SDTP-ERROR:.+") {
                    Write-Error $msg
                } else {
                    Write-Output $retval
                }

            } else {
                Write-Verbose "Reading text response ..."
                $reader = New-Object System.IO.StreamReader($stream)
                $retval = $reader.ReadToEnd()

                if ($retval -imatch "^SDTP-ERROR:.+") {
                    Write-Error $retval
                } else {
                    Write-Output $retval
                }
            }
        }

    } finally {
        if ($stream) {
            $stream.Dispose()
        }
        if ($connection) {
            $connection.Dispose()
        }
    }
}


<#
.SYNOPSIS
Gets data from the LAN clipboard.

.DESCRIPTION
Retrieves data stored in the LAN Clipboard (LCB) of the FEX server. The cmdlet
allows for retrieving the history of the clipboard as well as specific versions
stored on the server.

.PARAMETER Clipboard
The Clipboard parameter specifies the name of the clipboard to retrieve data
from. This parameter defaults to "_".

.PARAMETER Version
The Version parameter selects the version of the clipboard to retrieve. If not
specified, the latest version is retrieved.

.PARAMETER History
The History switch retrieves the history information for the clipboard.

.PARAMETER Raw
The Raw switch instructs the cmdlet to perform a binary read on the of the
output and returning a byte array.

.PARAMETER Server
The Server parameter specifies the host name or address of the server hosting
the LAN clipboard. This parameter defaults to fex.rus.uni-stuttgart.de.

.PARAMETER Port
The Port parameter specifies the port on which the LAN clipboard is listening
on. This parameter default to 80.

.INPUTS
This cmdlet does not accept any inputs from the pipeline.

.OUTPUTS
The value in the clipboard.

.EXAMPLE
Get-LanClipboard

.EXAMPLE
Get-LanClipboard data_2023

.EXAMPLE
Get-LanClipboard data_2023 5

.EXAMPLE
Get-LanClipboard -Clipboard data2023 -History

.EXAMPLE
Get-LanClipboard -Clipboard data_2023 -Version 5 -Server fextest.rus.uni-stuttgart.de

.EXAMPLE
Get-LanClipboard -Raw | Add-Content -Path clipboard.bin -Encoding Byte
#>
function Get-LanClipboard {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = "Get", Position = 0)]
        [Parameter(ParameterSetName = "History", Position = 0)]
        [string] $Clipboard = "_",

        [Parameter(ParameterSetName = "Get", Position = 1)]
        [int] $Version,

        [Parameter(Mandatory = $true, ParameterSetName = "History")]
        [switch] $History,

        [Parameter(ParameterSetName = "Get")]
        [switch] $Raw,

        [Parameter(ParameterSetName = "Get")]
        [Parameter(ParameterSetName = "History")]
        [string] $Server = "fex.rus.uni-stuttgart.de",

        [Parameter(ParameterSetName = "Get")]
        [Parameter(ParameterSetName = "History")]
        [int] $Port = 80
    )

    if ($History) {
        Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($Clipboard):q"

    } elseif ($Version) {
        Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($Clipboard):$Version" -Raw:$Raw

    } else {
        Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($Clipboard)" -Raw:$Raw
    }
}


<#
.SYNOPSIS
Writes data to the LAN clipboard.

.DESCRIPTION

.PARAMETER Value
The Value parameter specifies the data to be stored in the clipboard. Note
that this value will be converted into its string representation.

.PARAMETER Raw
The Raw parameter specifies an array of binary data to be stored in the
clipboard. No conversion will be performed on the bytes provided.

.PARAMETER Path
The Path parameter specifies the path to a file which of the content will be
stored in the clipboard. The file will be read in binary mode and no conversion
will be performed on its contents.

.PARAMETER Clipboard
The Clipboard parameter specifies the name of the clipboard to retrieve data
from. If the name of the clipboard starts with "public_", the server does not
enforce any access restrictions on the data. This parameter defaults to "_".

.PARAMETER Encoding
The Encoding parameter specifies the encoding for string-valued content passed
via the Value parameter. This parameter defaults to UTF-8.

.PARAMETER Server
The Server parameter specifies the host name or address of the server hosting
the LAN clipboard. This parameter defaults to fex.rus.uni-stuttgart.de.

.PARAMETER Port
The Port parameter specifies the port on which the LAN clipboard is listening
on. This parameter default to 80.

.INPUTS
The Value parameter is accepted via the pipeline.

.OUTPUTS
This cmdlet does not emit any outputs to the pipeline.

.EXAMPLE
Set-LanClipboard foo

.EXAMPLE
Set-LanClipboard bar data_2023

.EXAMPLE
Set-LanClipboard -Value bar -Clipboard data_2023

.EXAMPLE
Set-LanClipboard -Value bar -Clipboard data_2023 -Server fextest.rus.uni-stuttgart.de

.EXAMPLE
$env:COMPUTERNAME | Set-LanClipboard -Server fextest.rus.uni-stuttgart.de

.EXAMPLE
Set-LanClipboard -Value bar -Encoding ([System.Text.Encoding]::UTF32)

.EXAMPLE
Set-LanClipboard -Path image.png

.EXAMPLE
Set-LanClipboard -Raw (Get-Content -Path image.png -Encoding Byte)
#>
function Set-LanClipboard {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = "String", Position = 0, ValueFromPipeline = $true)]
        [string] $Value,

        [Parameter(ParameterSetName = "Binary", Position = 0)]
        [byte[]] $Raw,

        [Parameter(ParameterSetName = "File", Position = 0)]
        [string] $Path,

        [Parameter(ParameterSetName = "String", Position = 1)]
        [Parameter(ParameterSetName = "Binary", Position = 1)]
        [Parameter(ParameterSetName = "File", Position = 1)]
        [string] $Clipboard = "_",

        [Parameter(ParameterSetName = "String")]
        [System.Text.Encoding] $Encoding = [System.Text.Encoding]::UTF8,

        [string] $Server = "fex.rus.uni-stuttgart.de",
        [int] $Port = 80
    )

    begin { }

    process {
        if ($Value) {
            $Value | ForEach-Object {
                Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$Clipboard" -Method PUT -Body $Encoding.GetBytes("$_")
            }
            
        } elseif ($Data) {
            Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$Clipboard" -Method PUT -Body $Data

        } elseif ($Path) {
            $data = Get-Content -Path $Path -Encoding Byte
            Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$Clipboard" -Method PUT -Body $data
        }
    }

    end { }
}


# Export cmdlets that can be used by the end user.
Export-ModuleMember -Function Get-LanClipboard
Export-ModuleMember -Function Set-LanClipboard

# Export aliases for the above cmdlets.
New-Alias -Name glcb -Value Get-LanClipboard -Scope Global
New-Alias -Name lcbget -Value Get-LanClipboard -Scope Global
New-Alias -Name slcb -Value Set-LanClipboard -Scope Global
New-Alias -Name lcbput -Value Set-LanClipboard -Scope Global
