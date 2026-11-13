var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $report : Object:=New object("version"; Application version(*); "cases"; New collection())
var $doc; $body; $section; $range; $style; $item; $stop : Object
var $tabs; $paragraphs : Collection
var $kind; $leader; $name : Text
var $index; $type : Integer
$doc:=WP New()
$body:=WP Get body($doc)
WP SET TEXT($body; "A"+Char(9)+"日本😀é"+Char(13)+"B"+Char(9)+"12.34"+Char(13)+"C"; wk replace)
WP INSERT FORMULA($body; Formula("TAB"); wk append)
WP SET TEXT($body; Char(9)+"D"; wk append)
WP NEW BOOKMARK(WP Text range($body; 1; 3); "leading")
WP NEW BOOKMARK(WP Text range($body; wk start text; wk end text); "whole")
$range:=WP Insert break($body; wk continuous section break; wk append)
WP SET TEXT($body; "E"+Char(9)+"F"; wk append)
WP EXPORT DOCUMENT($doc; $root.file("Output/layout-base.4wp").platformPath; wk 4wp)
$report.base:=wp_layout_stats($doc)
For each ($kind; New collection("defaults"; "section"; "reset"; "maximum"))
	$doc:=WP Import document($root.file("Output/layout-base.4wp").platformPath)
	$section:=WP Get section($doc; 2)
	WP SET ATTRIBUTES($doc; wk column count; 2; wk column spacing; "18pt")
	If ($kind="section") | ($kind="reset")
		WP SET ATTRIBUTES($section; wk column count; 3; wk column spacing; "0.5cm"; wk column rule style; wk solid)
	End if
	If ($kind="reset")
		WP RESET ATTRIBUTES($section; wk column count; wk column spacing)
	End if
	If ($kind="maximum")
		WP SET ATTRIBUTES($doc; wk column count; 20; wk column spacing; "0pt")
	End if
	$name:="layout-columns-"+$kind
	WP EXPORT DOCUMENT($doc; $root.file("Output/"+$name+".4wp").platformPath; wk 4wp)
	$report.cases.push(New object("name"; $name; "stats"; wp_layout_stats($doc)))
End for each
$index:=0
For each ($type; New collection(wk left; wk right; wk center; wk decimal; wk bar))
	For each ($leader; New collection(""; "."; "-"; "_"; "ab"; "日"; "\""; "\\"; "😀"))
		$index:=$index+1
		$doc:=WP Import document($root.file("Output/layout-base.4wp").platformPath)
		$tabs:=New collection(New object(wk type; $type; wk offset; "36pt"; wk leading; $leader); New object(wk type; wk right; wk offset; "72pt"; wk leading; "."))
		$paragraphs:=WP Get elements(WP Get body($doc); wk type paragraph)
		WP SET ATTRIBUTES($paragraphs[0]; wk tabs; $tabs; wk tab default; New object(wk type; $type; wk offset; "18pt"; wk leading; $leader))
		$name:="layout-tabs-"+String($index)
		WP EXPORT DOCUMENT($doc; $root.file("Output/"+$name+".4wp").platformPath; wk 4wp)
		$doc:=WP Import document($root.file("Output/"+$name+".4wp").platformPath)
		$report.cases.push(New object("name"; $name; "type"; $type; "leader"; $leader; "stats"; wp_layout_stats($doc)))
	End for each
End for each
$doc:=WP Import document($root.file("Output/layout-base.4wp").platformPath)
$body:=WP Get body($doc)
$style:=WP New style sheet($doc; wk type paragraph; "Tabbed")
WP SET ATTRIBUTES($doc; wk tabs; New collection("24pt"); wk tab default; "12pt")
WP SET ATTRIBUTES($style; wk tabs; New collection(New object(wk type; wk center; wk offset; "48pt"; wk leading; ".")); wk tab default; "30pt")
$paragraphs:=WP Get elements($body; wk type paragraph)
WP SET ATTRIBUTES($paragraphs[0]; wk style sheet; "Tabbed")
WP SET ATTRIBUTES($paragraphs[1]; wk tabs; New collection(); wk tab default; "20pt")
WP EXPORT DOCUMENT($doc; $root.file("Output/layout-cascade.4wp").platformPath; wk 4wp)
$report.cascade:=wp_layout_stats($doc)
WP RESET ATTRIBUTES($paragraphs[0]; wk tabs; wk tab default)
WP RESET ATTRIBUTES($paragraphs[1]; wk tabs; wk tab default)
WP EXPORT DOCUMENT($doc; $root.file("Output/layout-cascade-reset.4wp").platformPath; wk 4wp)
$report.reset:=wp_layout_stats($doc)
var $picture : Picture
READ PICTURE FILE($root.file("Resources/checker.png").platformPath; $picture)
$doc:=WP Import document($root.file("Output/layout-base.4wp").platformPath)
$body:=WP Get body($doc)
WP INSERT PICTURE($body; $picture; wk append)
$range:=WP Insert break($body; wk paragraph break; wk append)
var $table : Object:=WP Insert table(WP Text range($body; wk end text; wk end text); wk append; wk include in range)
$range:=WP Table append row($table; "A"+Char(9)+"B"; "C")
$range:=WP Insert break($body; wk paragraph break; wk append)
WP SET TEXT($body; "END"; wk append)
WP EXPORT DOCUMENT($doc; $root.file("Output/layout-rich.4wp").platformPath; wk 4wp)
$report.rich:=wp_layout_stats($doc)
$section:=WP Get section($doc; 2)
var $header : Object:=WP New header($section)
WP SET TEXT($header; "HIDDEN HEADER"; wk replace)
WP EXPORT DOCUMENT($doc; $root.file("Output/layout-associated.4wp").platformPath; wk 4wp)
// Imported CSS cases establish cascade/reset and parallel-array semantics.
$report.imports:=New collection()
var $css; $html : Text
For each ($kind; New collection("cascade"; "inline"; "partial"; "empty"; "clear"; "zero"; "duplicate"; "negative"; "factory"; "gap"))
	$css:="p{white-space:pre-wrap}p.Tabbed{-d4-tab-stop-offset:48pt 30pt;-d4-tab-stop-type:center right;-d4-tab-stop-leading:'.' '-'}p._p1{-d4-tab-stop-offset:72pt 18pt;-d4-tab-stop-type:right left;-d4-tab-stop-leading:'_' ''}"
	$html:="<p class=\"Tabbed _p1\">A"+Char(9)+"B</p><p class=\"Tabbed\">C"+Char(9)+"D</p>"
	Case of
		: ($kind="inline")
			$html:="<p class=\"Tabbed _p1\" style=\"-d4-tab-stop-offset:60pt 12pt;-d4-tab-stop-type:decimal center;-d4-tab-stop-leading:'.' '_'\">A"+Char(9)+"B</p>"
		: ($kind="partial")
			$html:="<p class=\"Tabbed\" style=\"-d4-tab-stop-offset:60pt 12pt\">A"+Char(9)+"B</p>"
		: ($kind="empty")
			$html:="<p class=\"Tabbed\" style=\"-d4-tab-stop-offset:;-d4-tab-stop-type:;-d4-tab-stop-leading:\">A"+Char(9)+"B</p>"
		: ($kind="clear")
			$html:="<p class=\"Tabbed\" style=\"-d4-tab-stop-offset:30pt;-d4-tab-stop-type:right;-d4-tab-stop-leading:'-'\">A"+Char(9)+"B</p>"
		: ($kind="zero")
			$html:="<p style=\"-d4-tab-stop-offset:0pt 12pt\">A"+Char(9)+"B</p>"
		: ($kind="duplicate")
			$html:="<p style=\"-d4-tab-stop-offset:36pt 36pt 12pt\">A"+Char(9)+"B</p>"
		: ($kind="negative")
			$html:="<p style=\"-d4-tab-stop-offset:-1pt 12pt\">A"+Char(9)+"B</p>"
		: ($kind="factory")
			$html:="<p>A"+Char(9)+"B</p>"
		: ($kind="gap")
			$css:="div.section0{column-count:2;column-gap:10000pt}"
			$html:="<p>A"+Char(9)+"B</p>"
	End case
	$doc:=WP New("<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><style>"+$css+"</style></head><body>"+$html+"</body></html>")
	$name:="layout-import-"+$kind
	WP EXPORT DOCUMENT($doc; $root.file("Output/"+$name+".4wp").platformPath; wk 4wp)
	$report.imports.push(New object("name"; $name; "stats"; wp_layout_stats($doc)))
End for each
$root.file("Output/layout-report.json").setText(JSON Stringify($report; *))
