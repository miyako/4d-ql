#DECLARE() : Object
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("names"; New collection(); "operations"; New collection())
var wpBookmarkErrors : Collection
var $name : Text
var $doc; $body; $item; $range : Object
var $i : Integer:=0
var $names : Collection:=New collection(""; " "; "two words"; " leading "; "abc"; "ABC"; "日本語😀é")
$names.push("a"+Char(34)+Char(92)+"&<>"; "a.b"; "a-b"; "1name"; "__proto__"; "constructor")
$names.push("a"+Char(9)+"b"; "a"+Char(10)+"b"; "a"+Char(0)+"b")
$name:=""
For ($i; 1; 1024)
	$name:=$name+"x"
End for
$names.push(Substring($name; 1; 255); Substring($name; 1; 256); $name)
For ($i; 1; 127)
	$names.push("a"+Char($i)+"b")
End for
$names.push("é"; "é"; "日"; "😀"; "a　b"; "a b"; "a。b"; "a・b"; "a—b"; "a"+Char(8203)+"b"; "a"+Char(8205)+"b")
$names.push("a"+Char(133)+"b"; "a"+Char(159)+"b"; "a"+Char(8232)+"b")
$i:=0
For each ($name; $names)
	$i:=$i+1
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET TEXT($body; "A😀日éB"; wk replace)
	wpBookmarkErrors:=New collection()
	ON ERR CALL("wp_bookmark_error")
	WP NEW BOOKMARK(WP Text range($body; 2; 4); $name)
	ON ERR CALL("wp_web_error")
	$item:=New object("name"; $name; "errors"; wpBookmarkErrors; "after"; wp_range_stats($doc); "file"; "bookmark-name-"+String($i)+".4wp")
	$report.names.push($item)
	WP EXPORT DOCUMENT($doc; $root.file("Output/"+$item.file).platformPath; wk 4wp)
End for each
For each ($name; New collection("create"; "collapsed"; "duplicate"; "case"; "rename"; "renameDuplicate"; "delete"))
	$doc:=WP New()
	$body:=WP Get body($doc)
	WP SET TEXT($body; "A😀日éB"; wk replace)
	$item:=New object("name"; $name)
	WP EXPORT DOCUMENT($doc; $root.file("Output/bookmark-"+$name+"-original.4wp").platformPath; wk 4wp)
	WP NEW BOOKMARK(WP Text range($body; 2; 4); "日本語😀é")
	wpBookmarkErrors:=New collection()
	ON ERR CALL("wp_bookmark_error")
	Case of
		: ($name="collapsed")
			WP NEW BOOKMARK(WP Text range($body; 4; 4); "point")
		: ($name="duplicate")
			WP NEW BOOKMARK(WP Text range($body; 5; 7); "日本語😀é")
		: ($name="case")
			WP NEW BOOKMARK(WP Text range($body; 1; 2); "ABC")
			WP NEW BOOKMARK(WP Text range($body; 5; 7); "abc")
		: ($name="rename")
			$range:=WP Bookmark range($doc; "日本語😀é")
			WP DELETE BOOKMARK($doc; "日本語😀é")
			WP NEW BOOKMARK($range; "renamed_日本語😀é")
		: ($name="renameDuplicate")
			WP NEW BOOKMARK(WP Text range($body; 1; 2); "other")
			$range:=WP Bookmark range($doc; "日本語😀é")
			WP DELETE BOOKMARK($doc; "日本語😀é")
			WP NEW BOOKMARK($range; "other")
		: ($name="delete")
			WP DELETE BOOKMARK($doc; "日本語😀é")
	End case
	ON ERR CALL("wp_web_error")
	$item.errors:=wpBookmarkErrors
	$item.after:=wp_range_stats($doc)
	$report.operations.push($item)
	WP EXPORT DOCUMENT($doc; $root.file("Output/bookmark-"+$name+"-native.4wp").platformPath; wk 4wp)
End for each
var $bounds : Collection
For each ($name; New collection("cellText"; "cellPoint"; "cellTerminator"; "rowSeparator"; "wholeTable"; "listRange"))
	$doc:=WP Import document($root.file("Output/structure-table-original.4wp").platformPath)
	If ($name="listRange")
		$doc:=WP Import document($root.file("Output/structure-indentedList-original.4wp").platformPath)
	End if
	$body:=WP Get body($doc)
	Case of
		: ($name="cellText")
			$bounds:=New collection(8; 10)
		: ($name="cellPoint")
			$bounds:=New collection(10; 10)
		: ($name="cellTerminator")
			$bounds:=New collection(10; 11)
		: ($name="rowSeparator")
			$bounds:=New collection(14; 15)
		: ($name="wholeTable")
			$bounds:=New collection(8; 22)
		: ($name="listRange")
			$bounds:=New collection(11; 16)
	End case
	$item:=New object("name"; $name; "bounds"; $bounds)
	WP EXPORT DOCUMENT($doc; $root.file("Output/bookmark-"+$name+"-original.4wp").platformPath; wk 4wp)
	WP NEW BOOKMARK(WP Text range($body; $bounds[0]; $bounds[1]); "managed")
	$item.after:=wp_range_stats($doc)
	$report.operations.push($item)
	WP EXPORT DOCUMENT($doc; $root.file("Output/bookmark-"+$name+"-native.4wp").platformPath; wk 4wp)
End for each
return $report
