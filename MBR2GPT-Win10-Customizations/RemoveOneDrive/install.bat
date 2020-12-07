@ECHO OFF

:: Uninstall OneDrive for current user
  If Exist "%AppData%\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk" (
    START /WAIT %WINDIR%\SYSWOW64\onedrivesetup.exe /uninstall
)

:: Remove left over directories from Administrator Installation

IF Exist %UserProfile%\OneDrive (
  RD %UserProfile%\OneDrive /S /Q > NUL 2>&1
)

IF EXIST %UserProfile%\AppData\Local\Microsoft\OneDrive (
  RD %UserProfile%\AppData\Local\Microsoft\OneDrive /S /Q > NUL 2>&1
)

If Exist %SYSTEMDRIVE%\OneDriveTemp (
  RD %SYSTEMDRIVE%\OneDriveTemp /S /Q > NUL 2>&1
)

If Exist "%ProgramData%\Microsoft OneDrive" (
  RD "%ProgramData%\Microsoft OneDrive" /S /Q > NUL 2>&1
)

:: Prevent OneDrive Installation for all future users.
REG LOAD HKU\Default C:\Users\Default\ntuser.dat
REG DELETE HKU\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Run /v OneDriveSetup /f > NUL 2>&1
REG UNLOAD HKU\Default

:: Remove OneDrive link in Explorer Views
reg add HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6} /v System.IsPinnedToNameSpaceTree /d 0 /t REG_DWORD /f > NUL 2>&1 
