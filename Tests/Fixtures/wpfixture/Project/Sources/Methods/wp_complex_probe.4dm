#DECLARE() : Collection
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $results : Collection:=New collection()
var $shape; $kind; $name : Text
var $doc; $body; $table; $range; $item : Object
var $end; $i; $j; $columns; $point; $r; $c : Integer
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
For each ($shape; New collection("grid"; "uneven"; "empty"; "colspan"; "rowspan"; "rectangle"))
	For each ($kind; New collection("identity"; "typing"; "unicode"; "middleTyping"; "lastTyping"; "beforeTyping"; "afterTyping"; "split"; "lineBreak"; "paste"; "picture"; "cut"; "format"; "addRow"; "removeRow"; "addColumn"; "appendColumn"; "removeColumn"))
		$name:=$shape+"-"+$kind
		$doc:=WP New()
		$body:=WP Get body($doc)
		WP SET TEXT($body; "BEFORE"; wk replace)
		$range:=WP Insert break($body; wk paragraph break; wk append)
		$table:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
		$columns:=2
		Case of
			: ($shape="grid")
				$range:=WP Table append row($table; "AB"; "CD")
				$range:=WP Table append row($table; "EF"; "GH")
			: ($shape="empty")
				$range:=WP Table append row($table; ""; "")
				$range:=WP Table append row($table; ""; "")
			Else
				$columns:=3
				$range:=WP Table append row($table; "ABC"; "D"; "EF")
				$range:=WP Table append row($table; "G"; "HIJK"; "")
				$range:=WP Table append row($table; "LM"; ""; "NOP")
		End case
		Case of
			: ($shape="colspan")
				WP TABLE MERGE CELLS($table; 1; 1; 2; 1)
			: ($shape="rowspan")
				WP TABLE MERGE CELLS($table; 1; 1; 1; 2)
			: ($shape="rectangle")
				WP TABLE MERGE CELLS($table; 1; 1; 2; 2)
		End case
		WP SET TEXT($body; "AFTER"; wk append)
		$end:=WP Text range($body; wk start text; wk end text).end
		For ($i; 1; $end)
			For ($j; $i; $end)
				WP NEW BOOKMARK(WP Text range($body; $i; $j); "b"+String($i)+"_"+String($j))
			End for
		End for
		$item:=New object("name"; $name; "shape"; $shape; "operation"; $kind; "before"; wp_range_stats($doc))
		$range:=WP Text range($table; wk start text; wk end text)
		$item.tableStart:=$range.start
		$item.tableEnd:=$range.end
		$item.cells:=New collection()
		For ($r; 1; Choose($columns=2; 2; 3))
			For ($c; 1; $columns)
				$range:=WP Text range(WP Table get cells($table; $c; $r); wk start text; wk end text)
				$item.cells.push(New object("row"; $r; "column"; $c; "start"; $range.start; "end"; $range.end))
			End for
		End for
		WP EXPORT DOCUMENT($doc; $root.file("Output/complex-"+$name+"-original.4wp").platformPath; wk 4wp)
		$point:=8
		Case of
			: ($kind="middleTyping")
				$point:=WP Text range(WP Table get cells($table; 2; 2); wk start text; wk end text).start
			: ($kind="lastTyping")
				$point:=WP Text range(WP Table get cells($table; $columns; Choose($columns=2; 2; 3)); wk start text; wk end text).start
			: ($kind="beforeTyping")
				$point:=2
			: ($kind="afterTyping")
				$point:=$end-3
		End case
		$item.point:=$point
		Case of
			: (New collection("typing"; "middleTyping"; "lastTyping"; "beforeTyping"; "afterTyping").indexOf($kind)>=0)
				WP SET TEXT(WP Text range($body; $point; $point); "XY"; wk replace)
			: ($kind="unicode")
				WP SET TEXT(WP Text range($body; $point; $point); "😀日é"; wk replace)
			: ($kind="split")
				$range:=WP Insert break(WP Text range($body; $point; $point); wk paragraph break; wk replace)
			: ($kind="lineBreak")
				$range:=WP Insert break(WP Text range($body; $point; $point); wk line break; wk replace)
			: ($kind="paste")
				WP SET TEXT(WP Text range($body; $point; $point); "XY"+Char(13)+"Z"; wk replace)
			: ($kind="picture")
				WP INSERT PICTURE(WP Text range($body; $point; $point); $picture; wk replace)
			: ($kind="cut")
				If ($shape#"empty")
					WP SET TEXT(WP Text range($body; 8; 9); ""; wk replace)
				End if
			: ($kind="format")
				WP SET ATTRIBUTES(WP Text range($body; 8; 9); wk font bold; wk true)
			: ($kind="addRow")
				$range:=WP Table insert rows($table; 2)
			: ($kind="removeRow")
				WP TABLE DELETE ROWS($table; 1)
			: ($kind="addColumn")
				$range:=WP Table insert columns($table; 2)
			: ($kind="appendColumn")
				$range:=WP Table insert columns($table; $columns+1)
			: ($kind="removeColumn")
				WP TABLE DELETE COLUMNS($table; 1)
		End case
		$item.after:=wp_range_stats($doc)
		$results.push($item)
		WP EXPORT DOCUMENT($doc; $root.file("Output/complex-"+$name+"-native.4wp").platformPath; wk 4wp)
	End for each
End for each
return $results
