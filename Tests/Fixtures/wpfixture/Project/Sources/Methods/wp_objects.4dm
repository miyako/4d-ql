// Pictures (inline, anchored, background), text boxes, formulas and bookmarks.
var $doc : Object:=WP New()
var $body : Object:=WP Get body($doc)
var $r : Object
var $picture : Picture
READ PICTURE FILE(Get 4D folder(Database folder)+"Resources"+Folder separator+"checker.png"; $picture)
WP SET ATTRIBUTES($doc; wk title; "Objects probe")

WP SET TEXT($body; "Inline picture: "; wk append)
WP INSERT PICTURE(WP Text range($body; wk end text; wk end text); $picture; wk append)
var $inline : Object:=WP Get elements($body; wk type image)[0]
WP SET ATTRIBUTES($inline; wk width; "72pt"; wk height; "48pt"; wk image alternate text; "Checker"; wk border style; wk solid; wk border width; "1pt"; wk border color; "#000000")
WP SET TEXT(WP Text range($body; wk end text; wk end text); " after the picture."; wk append)

$r:=WP Insert break($body; wk paragraph break; wk append)
WP SET TEXT($body; "Formulas: date "; wk append)
WP INSERT FORMULA(WP Text range($body; wk end text; wk end text); Formula(Current date); wk append)
WP SET TEXT(WP Text range($body; wk end text; wk end text); ", time "; wk append)
WP INSERT FORMULA(WP Text range($body; wk end text; wk end text); Formula(String(Current time; HH MM SS)); wk append)
WP SET TEXT(WP Text range($body; wk end text; wk end text); ", field "; wk append)
WP INSERT FORMULA(WP Text range($body; wk end text; wk end text); Formula([Invoices]Customer); wk append)
WP SET TEXT(WP Text range($body; wk end text; wk end text); ", context "; wk append)
WP INSERT FORMULA(WP Text range($body; wk end text; wk end text); Formula(This.data.customer.name); wk append)
WP SET TEXT(WP Text range($body; wk end text; wk end text); ", named "; wk append)
WP INSERT FORMULA(WP Text range($body; wk end text; wk end text); New object("formula"; Formula(Uppercase("total")); "name"; "Grand total"); wk append)
WP SET TEXT(WP Text range($body; wk end text; wk end text); ", method "; wk append)
WP INSERT FORMULA(WP Text range($body; wk end text; wk end text); Formula(wp_value); wk append)
WP SET TEXT(WP Text range($body; wk end text; wk end text); "."; wk append)

$r:=WP Insert break($body; wk paragraph break; wk append)
WP SET TEXT($body; "A bookmarked sentence."; wk append)
var $p : Object:=WP Paragraph range(WP Text range($body; wk end text; wk end text))
WP NEW BOOKMARK($p; "intro")

$r:=WP Insert break($body; wk paragraph break; wk append)
WP SET TEXT($body; "Paragraph with a background image."; wk append)
$p:=WP Paragraph range(WP Text range($body; wk end text; wk end text))
WP SET ATTRIBUTES($p; wk background image; $picture; wk background display mode; wk replicated; wk min height; "60pt"; wk padding; "6pt")

var $anchored : Object:=WP Add picture($doc; $picture)
WP SET ATTRIBUTES($anchored; wk anchor layout; wk in front of text; wk anchor origin; wk paper box; wk anchor horizontal offset; "400pt"; wk anchor vertical offset; "100pt"; wk width; "96pt"; wk height; "64pt"; wk anchor page; 1)
var $behind : Object:=WP Add picture($doc; $picture)
WP SET ATTRIBUTES($behind; wk anchor layout; wk behind text; wk anchor horizontal align; wk right; wk anchor vertical align; wk bottom; wk width; "48pt"; wk height; "32pt"; wk image display mode; wk replicated; wk anchor page; wk anchor all; wk anchor section; wk anchor all)

var $box : Object:=WP New text box($doc; 1)
WP SET TEXT($box; "Text box content"; wk replace)
WP SET ATTRIBUTES($box; wk anchor horizontal offset; "300pt"; wk anchor vertical offset; "300pt"; wk width; "150pt"; wk height; "60pt"; wk background color; "#FFF2CC"; wk border style; wk solid; wk border width; "1pt"; wk border color; "#BF9000"; wk padding; "6pt"; wk anchor layout; wk text wrap square)

var $logo : Object:=WP Add picture($doc; $picture)
WP SET ATTRIBUTES($logo; wk image formula; Formula(This.data.logo); wk anchor layout; wk in front of text; wk anchor horizontal offset; "40pt"; wk anchor vertical offset; "700pt"; wk width; "48pt"; wk height; "32pt")
wp_save($doc; "objects")
