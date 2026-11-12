#DECLARE() : Collection
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $results : Collection:=New collection()
var $kind; $coverage; $name : Text
var $doc; $body; $table; $range; $item : Object
var $end; $i; $j : Integer
For each ($coverage; New collection("safe"; "boundary"))
For each ($kind; New collection("table"; "nested"; "indentedList"; "indent"; "listSplit"; "listJoin"; "listToggle"; "listPaste"; "listTyping"; "addRow"; "removeRow"; "addColumn"; "removeColumn"; "appendRow"; "removeLastRow"; "appendColumn"; "removeLastColumn"; "typing"; "cellStart"; "cellEnd"; "cut"; "splitCell"; "joinCell"; "pasteCell"; "listCell"; "pictureCell"; "unicodeCell"; "unicodeDelete"; "pictureDelete"; "pictureMove"; "insertTable"; "emptyCellTyping"))
	$name:=$kind
	If ($coverage="boundary")
		$name:="boundary-"+$kind
	End if
	If ($kind="nested")
		$doc:=WP New("<html><body><p>BEFORE</p><ul><li>AB<ul><li>CD</li><li>EF<ol><li>GH</li></ol></li></ul></li><li>IJ</li></ul><p>AFTER</p></body></html>")
	Else 
		If (New collection("indentedList"; "indent"; "listSplit"; "listJoin"; "listToggle"; "listPaste"; "listTyping").indexOf($kind)>=0)
			$doc:=WP New()
			$body:=WP Get body($doc)
			WP SET TEXT($body; "BEFORE"+Char(13)+"AB"+Char(13)+"CD"+Char(13)+"EF"+Char(13)+"GH"+Char(13)+"AFTER"; wk replace)
			WP SET ATTRIBUTES(WP Text range($body; 8; 19); wk list style type; wk disc)
			WP SET ATTRIBUTES(WP Text range($body; 11; 13); wk margin left; "24pt")
			WP SET ATTRIBUTES(WP Text range($body; 14; 16); wk margin left; "48pt"; wk list style type; wk decimal)
		Else
		If ($kind="insertTable")
			$doc:=WP New("<html><body><p>BEFORE</p><p>AFTER</p></body></html>")
		Else
		$doc:=WP New()
		$body:=WP Get body($doc)
		WP SET TEXT($body; "BEFORE"; wk replace)
		$range:=WP Insert break($body; wk paragraph break; wk append)
		$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
		If ($kind="emptyCellTyping")
			$range:=WP Table append row($table; ""; "")
			$range:=WP Table append row($table; ""; "")
		Else
			$range:=WP Table append row($table; "AB"; "CD")
			$range:=WP Table append row($table; "EF"; "GH")
		End if
		WP SET TEXT($body; "AFTER"; wk append)
		If ($kind="joinCell")
			$range:=WP Insert break(WP Text range($body; 9; 9); wk paragraph break; wk replace)
		End if
		If ($kind="unicodeDelete")
			WP SET TEXT(WP Text range($body; 9; 9); "😀日é"; wk replace)
		End if
		If (($kind="pictureDelete") | ($kind="pictureMove"))
			var $initialPicture : Picture
			READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $initialPicture)
			WP INSERT PICTURE(WP Text range($body; 9; 9); $initialPicture; wk replace)
		End if
		End if
		End if
	End if
	$body:=WP Get body($doc)
	$end:=WP Text range($body; wk start text; wk end text).end
	WP NEW BOOKMARK(WP Text range($body; 1; $end); "whole")
	For ($i; 1; $end)
		var $code : Integer:=Character code(WP Get text(WP Text range($body; $i; $i+1)))
		If ((($code<56320) | ($code>57343)) & (($kind#"unicodeDelete") | ($i#10)))
			WP NEW BOOKMARK(WP Text range($body; $i; $i); "point"+String($i))
			If (($i<$end) & (($code<55296) | ($code>56319)) & (($kind#"unicodeDelete") | ($i#9)))
				WP NEW BOOKMARK(WP Text range($body; $i; $i+1); "unit"+String($i))
			End if
		End if
	End for
	If ($coverage="boundary")
	For each ($i; New collection(1; 7; 8; 10; 11; 14; 15; 18; 21; 22))
		For each ($j; New collection(7; 8; 10; 11; 14; 15; 18; 21; 22))
			If (($i<$j) & ($j<=$end) & ($kind#"unicodeDelete"))
				WP NEW BOOKMARK(WP Text range($body; $i; $j); "boundary"+String($i)+"_"+String($j))
			End if
		End for each
	End for each
	End if
	WP NEW BOOKMARK(WP Text range($body; 3; $end-2); "cross")
	$item:=New object("name"; $name; "before"; wp_range_stats($doc))
	WP EXPORT DOCUMENT($doc; $root.file("Output/structure-"+$name+"-original.4wp").platformPath; wk 4wp)
	Case of
		: ($kind="addRow")
			$range:=WP Table insert rows($table; 2)
		: ($kind="removeRow")
			WP TABLE DELETE ROWS($table; 1)
		: ($kind="addColumn")
			$range:=WP Table insert columns($table; 2)
		: ($kind="removeColumn")
			WP TABLE DELETE COLUMNS($table; 1)
		: ($kind="appendRow")
			$range:=WP Table insert rows($table; 3)
		: ($kind="removeLastRow")
			WP TABLE DELETE ROWS($table; 2)
		: ($kind="appendColumn")
			$range:=WP Table insert columns($table; 3)
		: ($kind="removeLastColumn")
			WP TABLE DELETE COLUMNS($table; 2)
		: ($kind="typing")
			WP SET TEXT(WP Text range($body; 9; 9); "XY"; wk replace)
		: ($kind="cellStart")
			WP SET TEXT(WP Text range($body; 8; 8); "XY"; wk replace)
		: ($kind="cellEnd")
			WP SET TEXT(WP Text range($body; 10; 10); "XY"; wk replace)
		: ($kind="cut")
			WP SET TEXT(WP Text range($body; 8; 10); ""; wk replace)
		: ($kind="splitCell")
			$range:=WP Insert break(WP Text range($body; 9; 9); wk paragraph break; wk replace)
		: ($kind="joinCell")
			WP SET TEXT(WP Text range($body; 9; 10); ""; wk replace)
		: ($kind="pasteCell")
			WP SET TEXT(WP Text range($body; 9; 9); "XY"+Char(13)+"Z"; wk replace)
		: ($kind="listCell")
			WP SET ATTRIBUTES(WP Table get cells($table; 1; 1); wk list style type; wk disc)
		: ($kind="pictureCell")
			var $picture : Picture
			READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
			WP INSERT PICTURE(WP Text range($body; 9; 9); $picture; wk replace)
		: ($kind="unicodeCell")
			WP SET TEXT(WP Text range($body; 9; 9); "😀日é"; wk replace)
		: ($kind="emptyCellTyping")
			WP SET TEXT(WP Text range($body; 8; 8); "😀日"; wk replace)
		: ($kind="unicodeDelete")
			WP SET TEXT(WP Text range($body; 9; 12); ""; wk replace)
		: (($kind="pictureDelete") | ($kind="pictureMove"))
			WP SET TEXT(WP Text range($body; 9; 10); ""; wk replace)
			If ($kind="pictureMove")
				WP INSERT PICTURE(WP Text range($body; 19; 19); $initialPicture; wk replace)
			End if
		: ($kind="insertTable")
			$table:=WP Insert table(WP Text range($body; 7; 7); wk append; wk include in range)
			$range:=WP Table append row($table; ""; "")
			$range:=WP Table append row($table; ""; "")
		: ($kind="indent")
			WP SET ATTRIBUTES(WP Text range($body; 11; 13); wk margin left; "48pt")
		: ($kind="listSplit")
			$range:=WP Insert break(WP Text range($body; 12; 12); wk paragraph break; wk replace)
		: ($kind="listJoin")
			WP SET TEXT(WP Text range($body; 10; 11); ""; wk replace)
		: ($kind="listToggle")
			WP SET ATTRIBUTES(WP Text range($body; 8; 13); wk list style type; wk decimal)
		: ($kind="listPaste")
			WP SET TEXT(WP Text range($body; 12; 12); "XY"+Char(13)+"Z"; wk replace)
		: ($kind="listTyping")
			WP SET TEXT(WP Text range($body; 12; 12); "😀日"; wk replace)
	End case
	$item.after:=wp_range_stats($doc)
	$results.push($item)
	WP EXPORT DOCUMENT($doc; $root.file("Output/structure-"+$name+"-native.4wp").platformPath; wk 4wp)
End for each
End for each
return $results
