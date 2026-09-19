# Windows release checks

## 6.0.0 installer withdrawal

On 2026-09-09, Microsoft Defender reported `Trojan:Win32/Sabsik.FL.A!ml` for
`HomeTunnel-Setup-6.0.0-x64.exe` (SHA-256
`dd729a9d885b789ee037282513f61692eb280107594300b7bbd293e1e5944ceb`).
That EXE was withdrawn, and its entry was removed from the public checksum list.
Do not restore the quarantined installer or disable protection to run it.

The GUI and Agent extracted from the published 6.0.0 portable archive were not
detected by the same local Defender engine. A standard Inno Setup installer
containing the same payload also scanned without detections. These observations
isolate the reported issue to the custom installer packaging in the tested
environment; they are not a Microsoft false-positive determination or a guarantee
about every security product.

## Packaging from 6.0.1

- Use the official Inno Setup compiler, pinned by release URL and SHA-256 in
  `packaging/windows/inno-setup.json`.
- Use the native installer and uninstaller for files, shortcuts and application
  registration. The retired Go self-extractor, PowerShell shortcut command and
  batch uninstaller are no longer built or distributed.
- Include the application and third-party licenses in both the installer and
  portable archive.
- On isolated Windows CI runners, scan the actual EXE, ZIP, GUI and Agent using
  Microsoft Defender with recent definitions. File exclusions are ignored by
  custom scanning; protection settings are not weakened.
- Scan failures, unavailable scanners, stale definitions, missing files or
  changed hashes block publication. The release verifier matches scan results
  to the exact installer, archive and embedded programs.
- Exercise silent installation, installed-file hash checks and native
  uninstallation on the isolated runner.
- Attest the EXE and ZIP separately. Keep antivirus and installation reports in
  durable Release assets as well as Actions evidence. Keep the README download
  table focused on installable packages, with a separate verification link.

Antivirus scanning, Authenticode signing, SmartScreen reputation, dependency
auditing and build provenance are different checks. Passing one does not imply
the others pass. An unsigned installer may still receive an unknown-publisher or
reputation prompt even when the recorded Defender scan found no threats.
