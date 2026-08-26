Unicode True
ManifestSupportedOS all
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64
CRCCheck force

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "Sections.nsh"
!include "nsDialogs.nsh"

!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is required"
!endif
!ifndef FILE_VERSION
  !error "FILE_VERSION is required"
!endif
!ifndef DSH_VERSION
  !error "DSH_VERSION is required"
!endif
!ifndef LAUNCHER_VERSION
  !error "LAUNCHER_VERSION is required"
!endif
!ifndef PAYLOAD_ROOT
  !error "PAYLOAD_ROOT is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif
!ifndef ICON_FILE
  !error "ICON_FILE is required"
!endif
!ifndef ESTIMATED_SIZE_KB
  !error "ESTIMATED_SIZE_KB is required"
!endif

Name "DeepSeek Desktop ${PRODUCT_VERSION}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\DeepSeek Desktop"
InstallDirRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "InstallLocation"
Icon "${ICON_FILE}"
UninstallIcon "${ICON_FILE}"
BrandingText "社区维护 · 非 DeepSeek 官方软件"
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${FILE_VERSION}"
VIAddVersionKey /LANG=2052 "ProductName" "DeepSeek Desktop"
VIAddVersionKey /LANG=2052 "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=2052 "FileVersion" "${FILE_VERSION}"
VIAddVersionKey /LANG=2052 "CompanyName" "DeepSeek Desktop Community"
VIAddVersionKey /LANG=2052 "FileDescription" "DeepSeek Desktop 离线安装包（社区维护）"
VIAddVersionKey /LANG=2052 "LegalCopyright" "Community distribution; not affiliated with DeepSeek"

Var ModelMode
Var Plugins
Var CheckUpdates
Var AutoDownload
Var DesktopShortcut
Var KiloRadio
Var DeepSeekRadio
Var UpdateCheckBox
Var AutoDownloadCheckBox
Var DesktopShortcutCheckBox

!define MUI_ABORTWARNING
!define MUI_ICON "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"
!define MUI_WELCOMEPAGE_TITLE "安装 DeepSeek Desktop"
!define MUI_WELCOMEPAGE_TEXT "这是由社区维护的 DeepSeek Harness Windows 桌面封装，不是 DeepSeek 官方软件。$\r$\n$\r$\n安装包已包含 Node.js、Harness 和插件依赖；安装过程不会打开 PowerShell，也不会把依赖留到第一次启动。"
!insertmacro MUI_PAGE_WELCOME
Page custom OptionsPageCreate OptionsPageLeave
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\DeepSeek Desktop.exe"
!define MUI_FINISHPAGE_RUN_TEXT "启动 DeepSeek Desktop"
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\README.zh.md"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "查看中文说明"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

Function OptionsPageCreate
  !insertmacro MUI_HEADER_TEXT "首次配置" "模型路线、更新检查和快捷方式只在安装时选择。"
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 18u "默认模型路线"
  Pop $0
  CreateFont $1 "Microsoft YaHei UI" 10 700
  SendMessage $0 ${WM_SETFONT} $1 1

  ${NSD_CreateRadioButton} 0 24u 49% 20u "Kilo Auto Free（默认、免登录、无需 Key）"
  Pop $KiloRadio
  ${NSD_Check} $KiloRadio
  ${NSD_CreateRadioButton} 51% 24u 49% 20u "DeepSeek API（安装后填写 Key）"
  Pop $DeepSeekRadio

  ${NSD_CreateLabel} 0 49u 100% 34u "Kilo 和 LLM7 是远程匿名免费服务，不是本地模型。免费服务可能记录提示词用于服务改进，请勿提交敏感资料；额度、模型和可用性由服务方决定。"
  Pop $0

  ${NSD_CreateLabel} 0 92u 100% 18u "更新与快捷方式"
  Pop $0
  SendMessage $0 ${WM_SETFONT} $1 1
  ${NSD_CreateCheckbox} 0 116u 100% 18u "后台检查 DeepSeek 官方 Harness 与本社区发行版更新（只提示）"
  Pop $UpdateCheckBox
  ${NSD_Check} $UpdateCheckBox
  ${NSD_CreateCheckbox} 0 140u 100% 18u "发现社区新版后在后台下载，仍需我确认后才安装"
  Pop $AutoDownloadCheckBox
  ${NSD_CreateCheckbox} 0 164u 100% 18u "创建桌面快捷方式"
  Pop $DesktopShortcutCheckBox
  ${NSD_Check} $DesktopShortcutCheckBox

  ${NSD_CreateLabel} 0 192u 100% 32u "下一页可选择预装插件。插件文件全部包含在离线安装包中；取消勾选只会停用，不会在首次启动时下载。"
  Pop $0
  nsDialogs::Show
FunctionEnd

Function OptionsPageLeave
  ${NSD_GetState} $DeepSeekRadio $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $ModelMode "deepseek"
  ${Else}
    StrCpy $ModelMode "kilo"
  ${EndIf}
  ${NSD_GetState} $UpdateCheckBox $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $CheckUpdates "true"
  ${Else}
    StrCpy $CheckUpdates "false"
  ${EndIf}
  ${NSD_GetState} $AutoDownloadCheckBox $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $AutoDownload "true"
  ${Else}
    StrCpy $AutoDownload "false"
  ${EndIf}
  ${NSD_GetState} $DesktopShortcutCheckBox $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $DesktopShortcut "true"
  ${Else}
    StrCpy $DesktopShortcut "false"
  ${EndIf}
FunctionEnd

Section "DeepSeek Desktop 核心（必需）" SecCore
  SectionIn RO
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r /x "*.d.ts" /x "*.map" /x "launcher" "${PAYLOAD_ROOT}\*.*"
SectionEnd

Section "DSH Launcher ${LAUNCHER_VERSION}（桌面快捷方式）" SecLauncher
  SetOutPath "$INSTDIR\Launcher"
  File "${PAYLOAD_ROOT}\launcher\DSH Launcher.exe"
SectionEnd

Section "免费模型故障切换" SecFallback
SectionEnd

Section "视觉输入预检" SecVisionPreflight
SectionEnd

Section "Web 诊断" SecWebDiagnostics
SectionEnd

Section "会话导出" SecSessionExport
SectionEnd

Section "中文语音输入" SecMicInput
SectionEnd

Section "自动继续" SecAutoContinue
SectionEnd

Section "任务提醒角标" SecAttentionBadge
SectionEnd

Section "思考强度切换" SecModelSelection
SectionEnd

Section /o "辅助识图（实验性）" SecVisionSidecar
SectionEnd

Function .onInit
  StrCpy $ModelMode "kilo"
  StrCpy $CheckUpdates "true"
  StrCpy $AutoDownload "false"
  StrCpy $DesktopShortcut "true"
  !insertmacro UnselectSection ${SecVisionSidecar}
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/NO-LAUNCHER" $1
  ${IfNot} ${Errors}
    !insertmacro UnselectSection ${SecLauncher}
  ${EndIf}
  IfSilent nonOfficialNoticeDone
  MessageBox MB_OK|MB_ICONINFORMATION "重要说明：本软件是社区维护的 DeepSeek Harness 桌面封装，不是 DeepSeek 官方产品，也不代表 DeepSeek。安装包不包含任何 API Key。"
  nonOfficialNoticeDone:
FunctionEnd

Section -Finalize SecFinalize
  StrCpy $Plugins ""
  ${If} ${SectionIsSelected} ${SecFallback}
    StrCpy $Plugins "$Plugins,deepseek-desktop-free-fallback"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecVisionPreflight}
    StrCpy $Plugins "$Plugins,deepseek-desktop-vision-preflight"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecWebDiagnostics}
    StrCpy $Plugins "$Plugins,deepseek-desktop-web-diagnostics"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecSessionExport}
    StrCpy $Plugins "$Plugins,dsh-session-export"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecMicInput}
    StrCpy $Plugins "$Plugins,dsh-mic-input"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecAutoContinue}
    StrCpy $Plugins "$Plugins,auto-continue"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecAttentionBadge}
    StrCpy $Plugins "$Plugins,ui-attention-badge"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecModelSelection}
    StrCpy $Plugins "$Plugins,ui-model-selection"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SecVisionSidecar}
    StrCpy $Plugins "$Plugins,vision-sidecar"
  ${EndIf}

  DetailPrint "正在写入 profile 并验证插件链路…"
  ExecWait '"$INSTDIR\DeepSeek Configure.exe" "$ModelMode" "$Plugins" "$CheckUpdates" "$AutoDownload"' $0
  ${If} $0 != 0
    IfSilent configFailureDone
    MessageBox MB_OK|MB_ICONSTOP "安装配置或插件预检失败。已有用户配置已回档。请查看：$INSTDIR\logs\install-validation.log"
    configFailureDone:
    SetErrorLevel 2
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\卸载 DeepSeek Desktop.exe"
  CreateDirectory "$SMPROGRAMS\DeepSeek Desktop"
  CreateShortcut "$SMPROGRAMS\DeepSeek Desktop\DeepSeek Desktop.lnk" "$INSTDIR\DeepSeek Desktop.exe" "" "$INSTDIR\DeepSeek Desktop.exe" 0 SW_SHOWNORMAL "" "DeepSeek Desktop"
  CreateShortcut "$SMPROGRAMS\DeepSeek Desktop\卸载 DeepSeek Desktop.lnk" "$INSTDIR\卸载 DeepSeek Desktop.exe"
  ${If} ${SectionIsSelected} ${SecLauncher}
    CreateShortcut "$SMPROGRAMS\DeepSeek Desktop\DSH Launcher.lnk" "$INSTDIR\Launcher\DSH Launcher.exe" "" "$INSTDIR\Launcher\DSH Launcher.exe" 0 SW_SHOWNORMAL "" "DSH Launcher"
    CreateShortcut "$DESKTOP\DSH Launcher.lnk" "$INSTDIR\Launcher\DSH Launcher.exe" "" "$INSTDIR\Launcher\DSH Launcher.exe" 0 SW_SHOWNORMAL "" "DSH Launcher"
  ${Else}
    Delete "$DESKTOP\DSH Launcher.lnk"
    RMDir /r "$INSTDIR\Launcher"
  ${EndIf}
  ${If} $DesktopShortcut == "true"
    CreateShortcut "$DESKTOP\DeepSeek Desktop.lnk" "$INSTDIR\DeepSeek Desktop.exe" "" "$INSTDIR\DeepSeek Desktop.exe" 0 SW_SHOWNORMAL "" "DeepSeek Desktop"
  ${Else}
    Delete "$DESKTOP\DeepSeek Desktop.lnk"
  ${EndIf}

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "DisplayName" "DeepSeek Desktop"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "Publisher" "DeepSeek Desktop Community（非官方）"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "DisplayIcon" "$INSTDIR\DeepSeek Desktop.exe,0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "UninstallString" '"$INSTDIR\卸载 DeepSeek Desktop.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "QuietUninstallString" '"$INSTDIR\卸载 DeepSeek Desktop.exe" /S'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "NoRepair" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop" "EstimatedSize" ${ESTIMATED_SIZE_KB}
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\DeepSeek Desktop.exe" "" "$INSTDIR\DeepSeek Desktop.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\DeepSeek Desktop.exe" "Path" "$INSTDIR;$INSTDIR\runtime;$INSTDIR\app\node_modules\.bin"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecCore} "内置 Node.js 和 Harness ${DSH_VERSION}、桌面 WebView、插件助手和更新检查。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecLauncher} "安装独立的 DSH Launcher 管理器，并在桌面和开始菜单创建快捷方式；可以取消勾选。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecFallback} "Kilo 首次失败时切换到 LLM7 匿名免费路线；不会处理已经输出内容的请求。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecVisionPreflight} "在发送前检查图片能力并给出明确提示。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecWebDiagnostics} "提供本地网页服务和插件状态诊断。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecSessionExport} "把会话导出为 Markdown 或 JSON。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMicInput} "在 WebView 中使用浏览器语音转写，默认中文 zh-CN。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecAutoContinue} "网络中断后按规则自动发送“继续”。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecAttentionBadge} "等待确认或任务完成时显示窗口角标。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecModelSelection} "在模型选择器中切换支持的思考强度。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecVisionSidecar} "外挂视觉模型路由，匿名服务可能变化，默认不启用。"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  SetShellVarContext current
  IfSilent uninstallConfirmed
  MessageBox MB_YESNO|MB_ICONQUESTION "只卸载程序文件并保留模型、插件和会话配置：$LOCALAPPDATA\DeepSeek Harness Data$\r$\n$\r$\n继续卸载？" IDYES +2
  Abort
  uninstallConfirmed:
  Delete "$DESKTOP\DeepSeek Desktop.lnk"
  Delete "$DESKTOP\DSH Launcher.lnk"
  RMDir /r "$SMPROGRAMS\DeepSeek Desktop"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DeepSeek Desktop"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\DeepSeek Desktop.exe"
  RMDir /r "$INSTDIR"
SectionEnd
