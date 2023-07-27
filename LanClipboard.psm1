# Helper for making SDTP requests.
function Invoke-SdtpRequest {
    param(
        [string] $Server,
        [int] $Port,
        [string] $Path,
        [ValidateSet("GET", "PUT", "DELETE")] [string] $Method = "GET",
        [byte[]] $Body
    )

    try {
        if (-not $Server) {
            $Server = if ($env:LCB_SERVER) {
                $env:LCB_SERVER
            } else {
                "fex.rus.uni-stuttgart.de"
            }
        }

        if (-not $Port) {
            $Port = if ($env:LCB_PORT) {
                $env:LCB_PORT
            } else {
                80
            }
        }

        Write-Verbose "Connecting to $Server on port $Port ..."
        $connection = New-Object System.Net.Sockets.TcpClient($Server, $Port)
        $stream = $connection.GetStream();
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        # Special handling for DELETE: This is acutally a GET on the server, but
        # we do not want to emit the result in this case. Therefore, make the
        # DELETE a GET, but remember that it actually was a delete in the
        # original $Method parameter.
        $m = if ($Method -ieq "DELETE") { "GET" } else { $Method }
        Write-Verbose "$m $($Path)"
        $writer.Write("$m $($Path) SDTP/1.0`n`n")

        if ($Body) {
            Write-Verbose "Writing message body ..."
            $stream.Write($Body, 0, $Body.Length)
        }

        if ($m -ieq "GET") {
            Write-Verbose "Reading response ..."
            $ms = New-Object System.IO.MemoryStream
            $stream.CopyTo($ms)
            $retval = $ms.ToArray();

            # If there were an error message, this would be ASCII, so convert it
            # as such and check whether we want to emit an error. For
            # performance reasons, convert only as much as we need to determine
            # whether this is an error.
            if ($retval.Length -gt 11) {
                $msg = [System.Text.Encoding]::ASCII.GetString($retval, 0, 11)
                if ($msg -ieq "SDTP-ERROR:") {
                    $msg = [System.Text.Encoding]::ASCII.GetString($retval)
                    Write-Error $msg
                    return
                }
            }

            # Only emit something if the original request was GET. If we had a
            # delete and did not detect an error before, just emit nothing.
            if ($Method -ieq "GET") {
                Write-Output $retval
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


# Helper function to interpret responses.
function Convert-Response {
    param(
        [byte[]] $Data,
        [string] $Encoding
    )

    try {
        $e = [System.Text.Encoding]::GetEncoding($Encoding)
    } catch {
        $e = $null
    }

    if ($e) {
        Write-Verbose "Decode string using $Encoding ..."
        Write-Output $e.GetString($Data)
    } else {
        Write-Output $Data
    }
}


# Helper for autocompletion of text encodings.
$EncodingArgumentCompleter = {
    param($command, $parameter, $text, $ast, $fake)
    [System.Text.Encoding]::GetEncodings() | Where-Object { $_.Name -like "$text*" } | ForEach-Object { $_.Name }
}


<#
.SYNOPSIS
Gets data from the LAN clipboard.

.DESCRIPTION
Retrieves data stored in the LAN Clipboard (LCB) of the FEX server. The cmdlet
allows for retrieving the history of the clipboard as well as specific versions
stored on the server.

.PARAMETER Clipboard
The Clipboard parameter specifies the name of one or more clipboards to retrieve
data from. This parameter defaults to "_".

.PARAMETER Version
The Version parameter selects the version of the clipboard to retrieve. If not
specified, the latest version is retrieved.

.PARAMETER Encoding
The Encoding parameter performs a string conversion of the incoming byte stream
on demand. If this parameter is not set, the raw byte stream from the server
(bytes) will be emitted to the pipeline.

.PARAMETER History
The History switch retrieves the history information for the clipboard.

.PARAMETER Server
The Server parameter specifies the host name or address of the server hosting
the LAN clipboard. If this parameter is not specified, the LCB_SERVER
environment variable or fex.rus.uni-stuttgart.de in this order of preference.

.PARAMETER Port
The Port parameter specifies the port on which the LAN clipboard is listening
on. If this parameter is not specified, the LCB_PORT environment variable or
port 80 is used in this order of preference.

.INPUTS
You can pipe the names of the clipboards to retrieve to the cmdlet.

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
Get-LanClipboard -Clipboard data2023, _ -History | Where-Object { $_.Date -lt [DateTime]::Today }

.EXAMPLE
Get-LanClipboard -Clipboard data_2023 -Version 5 -Server fextest.rus.uni-stuttgart.de

.EXAMPLE
"data_2022", "data_2023" | Get-LanClipboard

.EXAMPLE
Get-LanClipboard data_2023 -Encoding UTF-8
#>
function Get-LanClipboard {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string[]] $Clipboard = "_",

        [Parameter(Position = 1)]
        [int] $Version,

        [Parameter(Position = 2)]
        [string] $Encoding,

        [switch] $History,
        [string] $Server,
        [int] $Port
    )

    begin { }

    process {
        $Clipboard | ForEach-Object {
            if ($History) {
                $clipboardName = $_
                Write-Verbose "Retrieving history of clipboard `"$name`" ..."
                $lines = Convert-Response -Data (Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($clipboardName):q") -Encoding us-ascii
                $lines = $lines.Split(@("`r`n", "`r", "`n"), [StringSplitOptions]::None)

                Write-Verbose "Processing history of clipboard `"$clipboardName`" ..."
                $lines | ForEach-Object {
                    if ($_ -imatch "^\s*Item\s+$([regex]::Escape($clipboardName)):(\d+)$") {
                        # We found a new entry. If we have an existing entry,
                        # emit it to the pipeline. Afterwards, create a new
                        # entry and add its basic properties, which are the
                        # name of the clipboard and the version number.
                        if ($item) {
                            Write-Output $item
                        }

                        Write-Verbose "Found version $($Matches[1])."
                        $item = New-Object -TypeName psobject
                        $item | Add-Member -NotePropertyName Clipboard -NotePropertyValue $clipboardName
                        $item | Add-Member -NotePropertyName Version -NotePropertyValue $Matches[1]

                    } elseif ($item -and ($_ -imatch "^\s*([^:]+):\s*(.+)$")) {
                        # This is an additional property for the current item,
                        # so just add it to the object.
                        $name = $Matches[1]
                        $value = if ($name -ieq "Date") { [DateTime] $Matches[2] } else { $Matches[2] }
                        $item | Add-Member -NotePropertyName $name -NotePropertyValue $value
                    }
                }

                # Emit the last item which was not written on finding the begin
                # of a new one.
                if ($item) {
                    Write-Output $item
                }

            } elseif ($Version) {
                Convert-Response -Data (Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($_):$Version") -Encoding $Encoding

            } else {
                Convert-Response -Data (Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($_)") -Encoding $Encoding
            }
        }
    }

    end { }
}


<#
.SYNOPSIS
Deletes data from thh LAN clipboard.

.DESCRIPTION
Removes a whole clipboard and all of its version by name or deletes individual
versions from a specific clipboard.

.PARAMETER Clipboard
The Clipboard parameter specifies the name of one or more clipboards to delete.

.PARAMETER Version
The Version parameter restricts the data to be deleted on a specific version.

.PARAMETER Server
The Server parameter specifies the host name or address of the server hosting
the LAN clipboard. If this parameter is not specified, the LCB_SERVER
environment variable or fex.rus.uni-stuttgart.de in this order of preference.

.PARAMETER Port
The Port parameter specifies the port on which the LAN clipboard is listening
on. If this parameter is not specified, the LCB_PORT environment variable or
port 80 is used in this order of preference.

.INPUTS
The cmdlet accepts the names of clipboards to remove as input.

.OUTPUTS
This cmdlet does not emit any outputs to the pipeline.

.EXAMPLE
Remove-LanClipboard foo

.EXAMPLE
Remove-LanClipboard data 1

.EXAMPLE
Remove-LanClipboard -Clipboard data -Version 1
#>
function Remove-LanClipboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]] $Clipboard,

        [Parameter(Position = 1)]
        [int] $Version,

        [string] $Server,
        [int] $Port
    )

    begin { }

    process {
        $Clipboard | ForEach-Object {
            if ($Version) {
                Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($_):$Version:d" -Method DELETE
            } else {
                Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($_):D" -Method DELETE
            }
        }
    }

    end { }
}


<#
.SYNOPSIS
Writes data to the LAN clipboard.

.DESCRIPTION
Connects to the FEX server and stores text or binary data to the LAN clipboard
there. If a non-existing clipboard is specified, the server will implicitly
create it. Pipeline will always be interpreted as text. Use the other parameter
sets if other behaviour is desired.

.PARAMETER Value
The Value parameter specifies the data to be stored in the clipboard.

.PARAMETER Path
The Path parameter specifies the path to a file that is to be transferred to
the LAN clipboard.

.PARAMETER Clipboard
The Clipboard parameter specifies the name of the clipboard to retrieve data
from. If the name of the clipboard starts with "public_", the server does not
enforce any access restrictions on the data. This parameter defaults to "_".

.PARAMETER Encoding
The Encoding parameter specifies the encoding for string-valued content passed
via the Value parameter. This parameter defaults to UTF-8.

.PARAMETER Server
The Server parameter specifies the host name or address of the server hosting
the LAN clipboard. If this parameter is not specified, the LCB_SERVER
environment variable or fex.rus.uni-stuttgart.de in this order of preference.

.PARAMETER Port
The Port parameter specifies the port on which the LAN clipboard is listening
on. If this parameter is not specified, the LCB_PORT environment variable or
port 80 is used in this order of preference.

.INPUTS
The Value parameter is accepted via the pipeline.

.OUTPUTS
This cmdlet does not emit any outputs to the pipeline.

.EXAMPLE
Set-LanClipboard foo -Encoding ([System.Text.Encoding]::UTF8)

.EXAMPLE
,(gc -Encoding Byte data.bin) | Set-LanClipboard foo -Clipboard data_2023

.EXAMPLE
Set-LanClipboard -Path data.bin -Clipboard data_2023
#>
function Set-LanClipboard {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName="Value", Mandatory, Position = 0, ValueFromPipeline)]
        $Value,

        [Parameter(ParameterSetName="Path", Mandatory)]
        [string] $Path,

        [Parameter(Position = 1)]
        [string] $Clipboard = "_",

        [string] $Encoding,

        [string] $Server,
        [int] $Port
    )

    begin { }

    process {
        if ($Value) {
            try {
                $e = [System.Text.Encoding]::GetEncoding($Encoding)
            } catch {
                $e = if ($Value -is [string]) {
                    Write-Verbose "Input value is a string, but no encoding is given."
                    [System.Text.Encoding]::GetEncoding($OutputEncoding.BodyName)
                } else {
                    $null
                }
            }

            $data = if ($e) { $e.GetBytes("$Value") } else { [byte[]] $Value }
        } elseif ($Path) {
            Write-Verbose "Reading raw data from `"$Path`" ..."
            $data = (Get-Content -Encoding byte $Path)
        }

        Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$Clipboard" -Method PUT -Body $data
    }

    end { }
}


# Export cmdlets that can be used by the end user.
Export-ModuleMember -Function Get-LanClipboard
Export-ModuleMember -Function Remove-LanClipboard
Export-ModuleMember -Function Set-LanClipboard

# Register a completer for Encodings.
Register-ArgumentCompleter -CommandName Get-LanClipboard -ParameterName Encoding -ScriptBlock $EncodingArgumentCompleter
Register-ArgumentCompleter -CommandName Set-LanClipboard -ParameterName Encoding -ScriptBlock $EncodingArgumentCompleter

# Export aliases for the above cmdlets.
New-Alias -Name glcb -Value Get-LanClipboard -Scope Global
New-Alias -Name lcbget -Value Get-LanClipboard -Scope Global
New-Alias -Name rlcb -Value Remove-LanClipboard -Scope Global
New-Alias -Name rmlcb -Value Remove-LanClipboard -Scope Global
New-Alias -Name lcbrm -Value Remove-LanClipboard -Scope Global
New-Alias -Name slcb -Value Set-LanClipboard -Scope Global
New-Alias -Name lcbput -Value Set-LanClipboard -Scope Global
