# mdt-local-account-setup

This is a two-stage PowerShell script primarily for use in an MDT Windows installation pipeline, after MDT finishes setting up the OS via Windows' built-in Administrator account, to create a local administrator account and disable the built-in Administrator account.
Effectively it's a built-in admin to local admin pipeline. 

**NOTE:** This tool was built with AI assistance. VM testing was done by yours truly. Do with that as you will.

## Requirements / Limitations:

- The tool is intended for Windows 11 machines configured via `MDT (Microsoft Deployment Toolkit)` and `unattend.xml`
- The Windows installation must be post-OOBE and post-setup. Otherwise `Configure-FirstBoot.ps1` (phase 2) will not execute properly.
- Must have built-in administrator account enabled
- Should not have a regular user account set up - or if there are, they will be left untouched UNLESS the existing account name matches that set up in the `param()` block in `Add-LocalAccount.ps1` as `$UserName` variable - in which case the existing account will be added to Administrators group (though automatic logon will only work if the existing account has no set password)
- Must be run elevated (as administrator), with both scripts in the same folder (this is because `Add-LocalAccount.ps1` copies `Configure-FirstBoot.ps1` from its own folder to execute later)
- Windows PowerShell 5.1 is required (built into Windows)
- The new account has no password set. This is for end user convenience. End users should set one for themselves, but many will not, therefore this is a known security shortcoming that exists for ease of use.
- The built-in Administrator account is briefly signed in and visible on first boot after `Add-LocalAccount.ps1` execution, before `Configure-FirstBoot.ps1` finishes and reboots into the new account.
- The built-in Administrator account is disabled, not deleted - it can be re-enabled later for recovery if needed.
- Logs stay behind on the C: drive (`FirstBoot.log` and `out.txt` in `C:\ProgramData\LocalAccSetup`)

**NOTE:** Tested in a VM only. Not yet verified in a real MDT task sequence.

## VM testing baseline:

As mentioned above, this tool has been tested in VMs (virtual machines) only - this was done due to infrastructural limitations on my part. Simply put, a full MDT setup on spare hardware would have introduced more overhead than would have been justified for my purposes.

However, I did take that fact into consideration when setting up the baseline VM image, as outlined below:

- Initial OOBE and setup completed via `OOBE\BYPASSNRO` into a local user account;
- Built-in Administrator account enabled via CMD `net user Administrator /active:yes`;
- Local user logged out and built in admin account logged in;
- Old account's profile deleted (folder + registry keys) via PowerShell `Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -Like "*\OldUser" } | Remove-CimInstance` where "`OldUser`" corresponds to the old account's name;
- Old account itself deleted via PowerShell `Remove-LocalUser -Name "OldUser"` where "`OldUser`" corresponds to the old account's name;
- Rebooted once to apply any hanging changes.
- Verified `HKLM:\SYSTEM\Setup` > `SystemSetupInProgress`, `OOBEInProgress`, `SetupType` and `SetupPhase` all share the value of 0. (This was done via PowerShell `Get-ItemProperty HKLM:\SYSTEM\Setup | Select SystemSetupInProgress, OOBEInProgress, SetupType, SetupPhase`)
- Snapshot taken of VM state. Each test was run on a clean baseline.

### Tests performed:

The following does not include all the in-between tests done to get the script running. The following are tests and how they were done once a working version was reached. So in other words, the following are the latest in a long line of tests run:

#### End-to-end test:

- Script executed in CMD via `powershell -ExecutionPolicy Bypass -File "Path\To\Add-LocalAccount.ps1"` where `Path\To\` represents the full path to the first script (`Add-LocalAccount.ps1`). 
    - Note that both scripts must be present in the same directory at the first script's execution.
- Verified local account creation via CMD `net user <User>` command
- Rebooted virtual machine
    - Automatically logged into built-in admin account for roughly one minute, then rebooted on its own and automatically logged into the new local account. 
    - **NOTE:** This delay is known and expected behavior so nothing to worry about - it takes time for the system to process the startup task and initiate the reboot.
- Verified built-in Administrator account state via CMD `net user Administrator`
- Verified the scheduled task was removed via CMD `schtasks /query /tn Configure-FirstBoot`
    - If task has been correctly removed, the command will throw `ERROR: The system cannot find the file specified.` - this is the normal and expected result, not an error in this context.
- Inspected log files (`FirstBoot.log` and `out.txt`) as they were saved to `C:\ProgramData\LocalAccSetup`
    - both logs report clean runs.

#### Deliberate failure test:

- Script executed in CMD via `powershell -ExecutionPolicy Bypass -File "Path\To\Add-LocalAccount.ps1"` where `Path\To\` represents the full path to the first script (`Add-LocalAccount.ps1`). 
    - Note that both scripts must be present in the same directory at the first script's execution.
- Verified local account creation via CMD `net user <User>` command
- Removed the local account via PowerShell `Remove-LocalUser -Name 'Kasutaja'` where "`Kasutaja`" refers to the default name of the created account.
- Verified deletion of local account via CMD `net user <User>`
- Rebooted virtual machine
    - Automatically logged into the built-in administrator account. No further restarts happened.
- Verified state of both users via CMD `net user <User>`
    - Created local account still gone, built-in administrator still enabled
- Verified the scheduled task was removed via CMD `schtasks /query /tn Configure-FirstBoot`
    - If the task has been correctly removed, the command will throw `ERROR: The system cannot find the file specified.` - this is the normal and expected result, not an error in this context.
- Inspected log files (`FirstBoot.log` and `out.txt`) as they were saved to `C:\ProgramData\LocalAccSetup`
    - both logs report missing user and early termination of script execution

The combination of the logged errors and script termination and account states on the virtual machine indicate that `Configure-FirstBoot.ps1` correctly terminates when the safety check fails (checks for presence of target account) before disabling the built-in Administrator account. This prevents a failed execution from locking you out of the machine.

## Usage

### Files

| File | Runs | Purpose |
|---|---|---|
| `Add-LocalAccount.ps1` | During the MDT task sequence, as the built-in Administrator | Creates the local account, copies `Configure-FirstBoot.ps1` to `C:\ProgramData\LocalAccSetup` and registers a one-time startup task |
| `Configure-FirstBoot.ps1` | Once, at the first boot after the task sequence, as SYSTEM | Removes the startup task, verifies the new account, sets up automatic logon, disables the built-in Administrator and reboots |

### Parameters (`Add-LocalAccount.ps1`)

| Parameter | Default | Description |
|---|---|---|
| `-UserName` | `Kasutaja` | Name of the local administrator account to create |
| `-UserDescription` | `Kohalik Kasutaja` | Description shown for the account |

The username is passed on to `Configure-FirstBoot.ps1` automatically via the scheduled task.

### Adding it to an MDT task sequence

1. Copy **both** scripts into the deployment share's `Scripts` folder.
2. Open the task sequence and, in the **State Restore** phase (e.g. under *Custom Tasks*), add a **Run PowerShell Script** step.
3. Set **PowerShell script** to:
   ```
   %SCRIPTROOT%\Add-LocalAccount.ps1
   ```
4. Optionally set **Parameters**, for example:
   ```
   -UserName "LocalAdmin" -UserDescription "Local Admin Account"
   ```
5. Place the step near the end of the task sequence, after applications and other customizations are installed.

On the first boot after the task sequence finishes, the machine briefly signs in as the built-in Administrator, `Configure-FirstBoot.ps1` runs in the background, and the machine reboots into the new account.

### Running it standalone

Run the following from an elevated command prompt, with both scripts in the same folder:

```
powershell -ExecutionPolicy Bypass -File "Path\To\Add-LocalAccount.ps1" -UserName "Kasutaja"
```

Then restart the machine. If you are using a virtual machine for testing, use a VM snapshot so you can roll back between runs.

### Logs and troubleshooting

Two logs are written to `C:\ProgramData\LocalAccSetup`:

- `FirstBoot.log` - this is a transcript of `Configure-FirstBoot.ps1`, every step plus any error it catches, including a failed safety check.
- `out.txt` - this one is output captured from the scheduled task's launch. Catches any errors that happen before the transcript starts (e.g. PowerShell failing to start the script).

If the machine stays on the built-in Administrator after reboot:

1. Check `FirstBoot.log` for an `ERROR` line.
2. If there is no log at all, check `out.txt`.
3. If neither file exists, the task never ran. Confirm Windows setup has completed: `SystemSetupInProgress` and `OOBEInProgress` under `HKLM:\SYSTEM\Setup` must both be `0`, otherwise Task Scheduler queues startup tasks without running them.

#### If all else fails:

- Ask AI (half-joking). All jokes aside, it can be a very useful tool for diagnosing these types of things.
    - **NOTE:** Just please keep in mind that AI is not a substitute for common sense. It can also make mistakes - it can make a lot of them, believe you me - and it may well believe it's right. So do exercise caution.
- If you cannot figure something out any other way, please open an issue in this repo, or contact me directly at `kresh@kreshy.com` - I will try and figure it out with you as best as I can, provided I can find the time.

## License:

Licensed under MIT license
(See the `LICENSE` file in project repository)
