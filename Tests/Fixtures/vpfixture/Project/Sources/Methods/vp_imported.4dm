#DECLARE($area : Text; $path : Text; $params : Object; $status : Object)
vp_log("IMPORT "+$path+" "+JSON Stringify($status))
If (Not($status.success))
	$params.result:=$status
	CANCEL
	return
End if
var $name : Text
Case of
	: ($params.stage=4)
		$name:="roundtrip"
	: ($params.stage=6)
		$name:="xlsx-roundtrip"
	: ($params.stage=7)
		$name:="enriched"
	: ($params.stage=9)
		$name:="enriched-xlsx-roundtrip"
End case
$params.formula:=Formula(vp_exported)
VP EXPORT DOCUMENT($area; $params.output.file($name+".4vp").platformPath; $params)
