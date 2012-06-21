#NoTrayIcon
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_outfile=essai2.exe
#AutoIt3Wrapper_Compression=3
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#include <Constants.au3>
#include <GUIConstantsEx.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>

Opt("GUIOnEventMode", 1) ; Change to OnEvent mode
Opt("TrayOnEventMode",1)
Opt("TrayMenuMode",1)

$appTitle = "Autocomplete tool (v0.1)"
$Form1 = GUICreate($appTitle, 483, 196, 243, 189)
$Label1 = GUICtrlCreateLabel("This tool is designed to autocomplete dialogs when performing checkin / checkout with Controlbuild", 8, 8, 473, 17)
$Label2 = GUICtrlCreateLabel("CR identifier (atvcm....)", 3, 32, 111, 17)
$Input1 = GUICtrlCreateInput("atvcm", 120, 32, 361, 21)
$Label3 = GUICtrlCreateLabel("Title of CR", 0, 56, 110, 17)
$Title = GUICtrlCreateEdit("", 120, 56, 361, 89)
GUICtrlSetData(-1, "")
$Validate = GUICtrlCreateButton("Validate", 0, 152, 480, 40, $WS_GROUP)
GUISetOnEvent($GUI_EVENT_CLOSE, "CLOSEClicked")
GUISetOnEvent($GUI_EVENT_MINIMIZE, "HideInTray")

GUICtrlSetOnEvent($Validate, "ChangeDescription")
TraySetOnEvent($TRAY_EVENT_PRIMARYUP,"ShowFromTray")
GUISetState(@SW_SHOW)



$CR_Number = "CR de test"
$Description = "Description de test"

While 1
	$window_id1 = "[TITLE:ClearCase;CLASS:#32770]"
	$window_id2 = "[TITLE:Enregistrement;CLASS:#32770]"
	$control_id = "[CLASSNN:Edit1]"
	$window_handle = 0

	If WinExists($window_id1) Then
		$window_handle = WinGetHandle($window_id1, "")
	EndIf

	If WinExists($window_id2) Then
		$window_handle = WinGetHandle($window_id2, "")
	EndIf

	If $window_handle Then
		WinWaitActive($window_handle, "")
		While WinExists($window_handle, "")
			$text = ControlGetText($window_handle, "", $control_id)
			If StringRegExp($text, '^\s*$') Then
				If StringRegExp($CR_Number, '^\s*$') Then
					ControlSend($window_handle, "", $control_id, $Description)
				Else
					ControlSend($window_handle, "", $control_id, $CR_Number & " : " & $Description)
				EndIf
			EndIf
		WEnd
		WinWaitClose($window_handle, "")
	EndIf
WEnd

Func ChangeDescription()
	$CR_Number = GUICtrlRead($Input1)
	$Description = GUICtrlRead($Title)
	MsgBox(0, "GUI Event", "You changed default text!")
EndFunc   ;==>ChangeDescription

Func HideInTray()
    GuiSetState(@SW_MINIMIZE)
	GuiSetState(@SW_HIDE)
	TraySetState(1) ; show

	If @OSVersion = "WIN_NT4" or @OSVersion = "WIN_ME" or @OSVersion = "WIN_98" or @OSVersion = "WIN_95" then
		TraySetToolTip ($appTitle  & " - click here to restore")
	Else
		Traytip ($appTitle, "click here to restore", 5)
	EndIf
EndFunc

Func ShowFromTray()
    GuiSetState(@SW_RESTORE)
    GuiSetState(@SW_Show)
    TraySetState(2) ; hide
EndFunc

Func CLOSEClicked()
	;Note: at this point @GUI_CTRLID would equal $GUI_EVENT_CLOSE,
	;and @GUI_WINHANDLE would equal $mainwindow
	MsgBox(0, "GUI Event", "You clicked CLOSE! Exiting...")
	Exit
EndFunc   ;==>CLOSEClicked