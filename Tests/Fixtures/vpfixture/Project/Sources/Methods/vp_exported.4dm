#DECLARE($area : Text; $path : Text; $params : Object; $status : Object)
vp_log("EXPORT "+$path+" "+JSON Stringify($status))
If (Not($status.success))
	$params.result:=$status
	CANCEL
	return
End if
Case of
	: ($params.stage=0)
		vp_layout($area)
		$params.stage:=1
		VP EXPORT DOCUMENT($area; $params.output.file("layout.4vp").platformPath; $params)
	: ($params.stage=1)
		$params.stage:=2
		$params.valuesOnly:=True
		VP EXPORT DOCUMENT($area; $params.output.file("values-only.4vp").platformPath; $params)
	: ($params.stage=2)
		$params.stage:=3
		$params.valuesOnly:=False
		$params.includeFormatInfo:=False
		VP EXPORT DOCUMENT($area; $params.output.file("no-format-info.4vp").platformPath; $params)
	: ($params.stage=3)
		$params.stage:=4
		$params.includeFormatInfo:=True
		$params.formula:=Formula(vp_imported)
		VP IMPORT DOCUMENT($area; $params.output.file("layout.4vp").platformPath; $params)
	: ($params.stage=4)
		$params.stage:=5
		VP EXPORT DOCUMENT($area; $params.output.file("layout.xlsx").platformPath; $params)
	: ($params.stage=5)
		$params.stage:=6
		$params.formula:=Formula(vp_imported)
		VP IMPORT DOCUMENT($area; $params.output.file("layout.xlsx").platformPath; $params)
	: ($params.stage=6)
		$params.stage:=7
		$params.formula:=Formula(vp_imported)
		vp_enrich($area; $params)
	: ($params.stage=7)
		$params.stage:=8
		VP EXPORT DOCUMENT($area; $params.output.file("enriched.xlsx").platformPath; $params)
	: ($params.stage=8)
		$params.stage:=9
		$params.formula:=Formula(vp_imported)
		VP IMPORT DOCUMENT($area; $params.output.file("enriched.xlsx").platformPath; $params)
	: ($params.stage=9)
		$params.result:={success: True; exports: 10; nativeImport: True; xlsxImport: True; enrichedImport: True; enrichedXlsxImport: True}
		ACCEPT
End case
