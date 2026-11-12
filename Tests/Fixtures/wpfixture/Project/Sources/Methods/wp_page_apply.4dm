#DECLARE($doc : Object; $kind : Text)
Case of
	: (($kind="letterLandscape") | ($kind="sectionsTarget"))
		WP SET ATTRIBUTES($doc; wk page width; "612pt"; wk page height; "792pt"; wk page orientation; wk landscape; wk page margin; "30pt")
	: ($kind="customPortrait")
		WP SET ATTRIBUTES($doc; wk page width; "630pt"; wk page height; "810pt"; wk page orientation; wk portrait; wk page margin; "0pt")
	: ($kind="a5")
		WP SET ATTRIBUTES($doc; wk page width; "420pt"; wk page height; "595pt"; wk page orientation; wk portrait; wk page margin; "36pt")
	: ($kind="fractionalMargin")
		WP SET ATTRIBUTES($doc; wk page margin top; "12.345mm"; wk page margin right; "0pt"; wk page margin bottom; "0.5in"; wk page margin left; "1.25cm")
	: ($kind="wide")
		WP SET ATTRIBUTES($doc; wk page width; "900pt"; wk page height; "500pt"; wk page orientation; wk landscape; wk page margin; "36pt")
End case
