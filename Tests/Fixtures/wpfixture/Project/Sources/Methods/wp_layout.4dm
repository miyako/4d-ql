// Page setup, sections, headers/footers, columns, breaks and page-number formulas.
var $doc : Object:=WP New()
var $body : Object:=WP Get body($doc)
var $r : Object
WP SET ATTRIBUTES($doc; wk title; "Layout probe")
WP SET ATTRIBUTES($doc; wk page orientation; wk landscape; wk page margin; "1.5cm"; wk page margin top; "2cm")
WP SET ATTRIBUTES($doc; wk background color; "#FFFDF5")

var $s1 : Object:=WP Get section($doc; 1)
WP SET ATTRIBUTES($s1; wk section name; "Introduction")
var $header : Object:=WP New header($s1)
WP SET TEXT($header; "Header of section 1 — "; wk append)
WP INSERT FORMULA(WP Text range($header; wk end text; wk end text); Formula(This.sectionName); wk append)
WP SET ATTRIBUTES(WP Paragraph range($header); wk text align; wk center; wk border style bottom; wk solid; wk border width bottom; "1pt")
var $footer : Object:=WP New footer($s1)
WP SET TEXT($footer; "Page "; wk append)
WP INSERT FORMULA(WP Text range($footer; wk end text; wk end text); Formula(This.pageNumber); wk append)
WP SET TEXT(WP Text range($footer; wk end text; wk end text); " of "; wk append)
WP INSERT FORMULA(WP Text range($footer; wk end text; wk end text); Formula(This.pageCount); wk append)
WP SET ATTRIBUTES(WP Paragraph range($footer); wk text align; wk right)

WP SET TEXT($body; "Section 1 starts here. "; wk append)
var $i : Integer
For ($i; 1; 3)
	$r:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; "Paragraph "+String($i)+" of section one. Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."; wk append)
End for
$r:=WP Insert break($body; wk page break; wk append)
WP SET TEXT($body; "After a page break."; wk append)

$r:=WP Insert break($body; wk section break; wk append)
WP SET TEXT($body; "Section 2 with two columns. "; wk append)
var $s2 : Object:=WP Get section($doc; 2)
WP SET ATTRIBUTES($s2; wk section name; "Columns"; wk column count; 2; wk column spacing; "1cm"; wk column rule style; wk solid; wk column rule width; "0.5pt"; wk column rule color; "#999999")
For ($i; 1; 4)
	$r:=WP Insert break($body; wk paragraph break; wk append)
	WP SET TEXT($body; "Column text "+String($i)+". Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam."; wk append)
End for
$r:=WP Insert break($body; wk column break; wk append)
WP SET TEXT($body; "After a column break."; wk append)

$r:=WP Insert break($body; wk continuous section break; wk append)
WP SET TEXT($body; "Section 3 after a continuous section break, with a different first page."; wk append)
var $s3 : Object:=WP Get section($doc; 3)
WP SET ATTRIBUTES($s3; wk section name; "Appendix"; wk column count; 1; wk page first number; 10)
var $h2 : Object:=WP Get header($s2)
WP SET TEXT($h2; "Columns header"; wk replace)
var $h3 : Object:=WP Get header($s3)
WP SET TEXT($h3; "Regular header of section 3"; wk replace)
var $first : Object:=WP New subsection($s3; wk first page)
var $fh : Object:=WP Get header($first)
WP SET TEXT($fh; "First page header of section 3"; wk replace)

wp_save($doc; "layout")
