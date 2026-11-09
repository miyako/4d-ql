var $area : Integer
var $blob : Blob
var $out : Text
Get database parameter(User param value; $out)
LOG EVENT(Into system standard outputs; "QR BEGIN\n")
$area:=QR New offscreen area
QR SET REPORT TABLE($area; 1)
LOG EVENT(Into system standard outputs; "QR AREA "+String($area)+"\n")
QR REPORT TO BLOB($area; $blob)
File($out+"/empty.4qr").setContent($blob)
LOG EVENT(Into system standard outputs; "QR BYTES "+String(BLOB size($blob))+"\n")
QR INSERT COLUMN($area; 1; "Customer")
QR REPORT TO BLOB($area; $blob)
File($out+"/column.4qr").setContent($blob)
var $baseline : Blob
$baseline:=$blob
var $i : Integer
var $name : Text
var $picture : Picture
For ($i; 1; 32)
	LOG EVENT(Into system standard outputs; "PROBE "+String($i)+"\n")
	QR BLOB TO REPORT($area; $baseline)
	Case of
		: ($i=1)
			$name:="title"
			QR SET INFO COLUMN($area; 1; "TITLE MARKER"; "Customer"; 0; -1; 1; "")
		: ($i=2)
			$name:="width"
			QR SET INFO COLUMN($area; 1; "Customer"; "Customer"; 0; 173; 1; "")
		: ($i=3)
			$name:="hidden"
			QR SET INFO COLUMN($area; 1; "Customer"; "Customer"; 1; -1; 1; "")
		: ($i=4)
			$name:="repeat"
			QR SET INFO COLUMN($area; 1; "Customer"; "Customer"; 0; -1; 0; "")
		: ($i=5)
			$name:="format"
			QR SET INFO COLUMN($area; 1; "Customer"; "Customer"; 0; -1; 1; "###,##0.00")
		: ($i=6)
			$name:="formula"
			QR SET INFO COLUMN($area; 1; "Customer"; "123+456"; 0; -1; 1; "")
		: ($i=7)
			$name:="header"
			QR SET HEADER AND FOOTER($area; 1; "LEFT"; "CENTER"; "RIGHT"; 73)
		: ($i=8)
			$name:="footer"
			QR SET HEADER AND FOOTER($area; 2; "BOTTOM"; ""; "PAGE #"; 41)
		: ($i=9)
			$name:="font"
			QR SET TEXT PROPERTY($area; 1; -1; 10; "Courier New")
		: ($i=10)
			$name:="size"
			QR SET TEXT PROPERTY($area; 1; -1; 2; 23)
		: ($i=11)
			$name:="bold"
			QR SET TEXT PROPERTY($area; 1; -1; 3; 1)
		: ($i=12)
			$name:="italic"
			QR SET TEXT PROPERTY($area; 1; -2; 4; 1)
		: ($i=13)
			$name:="underline"
			QR SET TEXT PROPERTY($area; 1; -1; 5; 1)
		: ($i=14)
			$name:="textcolor"
			QR SET TEXT PROPERTY($area; 1; -1; 6; 0x00123456)
		: ($i=15)
			$name:="background"
			QR SET TEXT PROPERTY($area; 1; -1; 8; 0x00654321)
		: ($i=16)
			$name:="alternate"
			QR SET TEXT PROPERTY($area; 1; -2; 9; 0x00123456)
		: ($i=17)
			$name:="justify"
			QR SET TEXT PROPERTY($area; 1; -1; 7; 3)
		: ($i=18)
			$name:="hidetitle"
			QR SET INFO ROW($area; -1; 1)
		: ($i=19)
			$name:="hidedetail"
			QR SET INFO ROW($area; -2; 1)
		: ($i=20)
			$name:="sum"
			QR SET TOTALS DATA($area; 1; -3; 1)
		: ($i=21)
			$name:="totaltext"
			QR SET TOTALS DATA($area; 1; -3; "TOTAL ##S")
		: ($i=22)
			$name:="cross"
			QR SET REPORT KIND($area; 2)
		: ($i=23)
			$name:="left"
			QR SET TEXT PROPERTY($area; 1; -1; 7; 1)
		: ($i=24)
			$name:="center"
			QR SET TEXT PROPERTY($area; 1; -1; 7; 2)
		: ($i=25)
			$name:="hidetotal"
			QR SET INFO ROW($area; -3; 1)
		: ($i=26)
			$name:="unicode"
			QR SET INFO COLUMN($area; 1; "日本語 café 😀"; "Customer"; 0; 200; 1; "")
		: ($i=27)
			$name:="border"
			QR SET BORDERS($area; 1; -1; 1; 4; 0x00123456)
		: ($i=28)
			$name:="bordertop"
			QR SET BORDERS($area; 1; -1; 2; 4; 0x00123456)
		: ($i=29)
			$name:="borderright"
			QR SET BORDERS($area; 1; -1; 4; 4; 0x00123456)
		: ($i=30)
			$name:="borderhorizontal"
			QR SET BORDERS($area; 1; -1; 32; 4; 0x00123456)
		: ($i=31)
			$name:="bordervertical"
			QR SET BORDERS($area; 1; -1; 16; 4; 0x00123456)
		: ($i=32)
			$name:="picture"
			File($out+"/marker.svg").setText("<svg xmlns='http://www.w3.org/2000/svg' width='20' height='10'><rect width='20' height='10' fill='#123456'/></svg>")
			READ PICTURE FILE(File($out+"/marker.svg").platformPath; $picture)
			QR SET HEADER AND FOOTER($area; 1; "With picture"; ""; ""; 40; $picture; 2)
	End case
	QR REPORT TO BLOB($area; $blob)
	File($out+"/"+$name+".4qr").setContent($blob)
	LOG EVENT(Into system standard outputs; $name+" "+String(BLOB size($blob))+"\n")
End for
QR DELETE OFFSCREEN AREA($area)
QUIT 4D
