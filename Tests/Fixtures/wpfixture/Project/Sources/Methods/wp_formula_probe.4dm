#DECLARE() : Collection
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $results : Collection:=New collection()
var $kind; $operation : Text
var $doc; $body; $formula; $item; $range : Object
var $i; $end : Integer
For each ($kind; New collection("uncomputed"; "computed"; "empty"; "nbsp"; "zero"; "unicode"; "named"; "nested"; "supplied"; "suppliedZero"; "suppliedEmpty"; "suppliedNbsp"; "picture"; "dataSource"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET ATTRIBUTES($doc; wk title; "Formula "+$kind; wk author; "Native formula oracle"; wk subject; "Protected surrounding edits")
	WP SET TEXT($body; "AB"; wk replace)
	Case of
		: ($kind="empty")
			$formula:=Formula("")
		: ($kind="nbsp")
			$formula:=Formula(Char(160))
		: ($kind="zero")
			$formula:=Formula(0)
		: ($kind="unicode")
			$formula:=Formula("😀日é")
		Else
			$formula:=Formula(Uppercase("saved"))
	End case
	If ($kind="named")
		WP INSERT FORMULA($body; New object("formula"; $formula; "name"; "Named <source>"); wk append)
	Else
		WP INSERT FORMULA($body; $formula; wk append)
	End if
	WP SET TEXT($body; "CD"; wk append)
	If ($kind="nested")
		WP SET ATTRIBUTES(WP Text range($body; 3; 4); wk font bold; wk true; wk text color; "#123456")
	End if
	If (Position("supplied"; $kind)=1)
		var $saved : Text:="SAVED"
		Case of
			: ($kind="suppliedZero")
				$saved:="0"
			: ($kind="suppliedEmpty")
				$saved:=""
			: ($kind="suppliedNbsp")
				$saved:=Char(160)
		End case
		$doc:=WP New("<html><body><p>AB<span style=\"-d4-ref:'Uppercase:C13(&quot;saved&quot;)'\"><span style=\"font-weight:bold\">"+$saved+"</span></span>CD</p></body></html>")
		$body:=WP Get body($doc)
	End if
	If ($kind="picture")
		$doc:=WP New()
		$body:=WP Get body($doc)
		WP SET TEXT($body; "AB"; wk replace)
		var $picture : Picture
		READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
		var $image : Object:=WP Add picture($doc; $picture)
		WP SET ATTRIBUTES($image; wk image formula; Formula(This.data.logo); wk anchor layout; wk in front of text)
		WP SET TEXT($body; "CD"; wk append)
	End if
	If ($kind="dataSource")
		var $table : Object:=WP Insert table($body; wk append; wk include in range)
		$range:=WP Table append row($table; "item")
		WP SET ATTRIBUTES($table; wk datasource; Formula(This.data.lines))
	End if
	If (New collection("computed"; "empty"; "nbsp"; "zero"; "unicode"; "named").indexOf($kind)>=0)
		WP COMPUTE FORMULAS($doc)
	End if
	$end:=WP Text range($body; wk start text; wk end text).end
	WP NEW BOOKMARK(WP Text range($body; 1; $end); "whole")
	For ($i; 1; $end)
		WP NEW BOOKMARK(WP Text range($body; $i; $i); "point"+String($i))
		If ($i<$end)
			WP NEW BOOKMARK(WP Text range($body; $i; $i+1); "unit"+String($i))
		End if
	End for
	WP NEW BOOKMARK(WP Text range($body; 2; 4); "crossStart")
	WP NEW BOOKMARK(WP Text range($body; 3; 5); "crossEnd")
	$item:=New object("name"; $kind; "before"; wp_range_stats($doc); "native"; wp_web_stats($doc; False); "operations"; New collection())
	WP EXPORT DOCUMENT($doc; $root.file("Output/formula-"+$kind+"-original.4wp").platformPath; wk 4wp)
	WP EXPORT DOCUMENT($doc; $root.file("Output/formula-"+$kind+"-visible.4wp").platformPath; wk 4wp; New object(wk visible references; False; wk recompute formulas; False))
	If (($kind#"picture") & ($kind#"dataSource"))
		For each ($operation; New collection("before"; "start"; "end"; "after"; "cut"; "replace"; "splitBefore"; "splitAfter"; "splitStart"; "splitEnd"; "joinBefore"; "joinAfter"; "joinStart"; "joinEnd"; "break"; "paste"; "pasteBefore"; "pasteStart"; "pasteEnd"; "format"))
			var $copy : Object:=WP Import document($root.file("Output/formula-"+$kind+"-original.4wp").platformPath)
			var $copyBody : Object:=WP Get body($copy)
			Case of
				: ($operation="before")
					WP SET TEXT(WP Text range($copyBody; 2; 2); "😀日"; wk replace)
				: ($operation="start")
					WP SET TEXT(WP Text range($copyBody; 3; 3); "XY"; wk replace)
				: ($operation="end")
					WP SET TEXT(WP Text range($copyBody; 4; 4); "XY"; wk replace)
				: ($operation="after")
					WP SET TEXT(WP Text range($copyBody; 5; 5); "😀日"; wk replace)
				: ($operation="cut")
					WP SET TEXT(WP Text range($copyBody; 1; 3); ""; wk replace)
				: ($operation="replace")
					WP SET TEXT(WP Text range($copyBody; 4; 6); ""; wk replace)
					WP SET TEXT(WP Text range($copyBody; 4; 4); "XY"; wk replace)
				: ($operation="splitBefore")
					$range:=WP Insert break(WP Text range($copyBody; 2; 2); wk paragraph break; wk replace)
				: ($operation="splitAfter")
					$range:=WP Insert break(WP Text range($copyBody; 5; 5); wk paragraph break; wk replace)
				: (($operation="splitStart") | ($operation="joinStart"))
					$range:=WP Insert break(WP Text range($copyBody; 3; 3); wk paragraph break; wk replace)
					If ($operation="joinStart")
						WP SET TEXT(WP Text range($copyBody; 3; 4); ""; wk replace)
					End if
				: (($operation="splitEnd") | ($operation="joinEnd"))
					$range:=WP Insert break(WP Text range($copyBody; 4; 4); wk paragraph break; wk replace)
					If ($operation="joinEnd")
						WP SET TEXT(WP Text range($copyBody; 4; 5); ""; wk replace)
					End if
				: ($operation="joinBefore")
					$range:=WP Insert break(WP Text range($copyBody; 2; 2); wk paragraph break; wk replace)
					WP SET TEXT(WP Text range($copyBody; 2; 3); ""; wk replace)
				: ($operation="joinAfter")
					$range:=WP Insert break(WP Text range($copyBody; 5; 5); wk paragraph break; wk replace)
					WP SET TEXT(WP Text range($copyBody; 5; 6); ""; wk replace)
				: ($operation="break")
					$range:=WP Insert break(WP Text range($copyBody; 5; 5); wk line break; wk replace)
				: ($operation="paste")
					WP SET TEXT(WP Text range($copyBody; 5; 5); "XY"+Char(13)+"Z"; wk replace)
				: ($operation="pasteBefore")
					WP SET TEXT(WP Text range($copyBody; 2; 2); "XY"+Char(13)+"Z"; wk replace)
				: ($operation="pasteStart")
					WP SET TEXT(WP Text range($copyBody; 3; 3); "XY"+Char(13)+"Z"; wk replace)
				: ($operation="pasteEnd")
					WP SET TEXT(WP Text range($copyBody; 4; 4); "XY"+Char(13)+"Z"; wk replace)
				: ($operation="format")
					WP SET ATTRIBUTES(WP Text range($copyBody; 4; 6); wk font bold; wk true)
			End case
			$item.operations.push(New object("name"; $operation; "after"; wp_range_stats($copy); "native"; wp_web_stats($copy; False)))
			WP EXPORT DOCUMENT($copy; $root.file("Output/formula-"+$kind+"-"+$operation+"-native.4wp").platformPath; wk 4wp)
		End for each
	End if
	$results.push($item)
End for each
return $results
