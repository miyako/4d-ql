ON ERR CALL("vp_err")
var $out : 4D.Folder
$out:=Folder("/PACKAGE/Output")
If (Not($out.exists))
	$out.create()
End if
var $params; $result : Object
$params:={area: "vpFixture"; onEvent: Formula(vp_event); autoQuit: False; timeout: 60; result: Null}
$params.output:=$out
$params.stage:=0
vp_log("BEGIN offscreen View Pro")
$result:=VP Run offscreen area($params)
If ($result=Null)
	vp_log("ERROR offscreen timeout or cancelled")
	$out.file("error.txt").setText("Offscreen timeout or cancelled")
Else
	$out.file("result.json").setText(JSON Stringify($result; *))
	vp_log("DONE "+JSON Stringify($result))
End if
QUIT 4D
