<!-- RCS Identication ; $Revision$ ; $Date$ -->

  [IF status=auth]
Po�adujete p�ihl�en� do konference [list]. 
<BR>Pro potvrzen� Va�eho po�adavku, stiskn�te tla��tko dole :<BR>
	<BR>

	<FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[user->email]">
	  <INPUT TYPE="submit" NAME="action_subscribe" VALUE="P�ihla�uji se do konference [list]">
	</FORM>

  [ELSIF status=notauth_passwordsent]
Po�adujete p�ihl�en� do konference [list]. 
	<BR><BR>
Pro potvrzen� Va�� identity, a abychom zabr�nili ciz�m osob�m ve Va�em p�ihl�en� 
proti Va�� v�li, V�m bude odesl�na zprava obsahuj�c� Va�e heslo.
<BR><BR>
Zkontrolujte si Va�i schr�nku a vlo�te heslo. T�mto potvrd�te Va�e p�ihl�en� 
do konference [list].
	
        <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>e-mail address</B> </FONT>[email]<BR>
	  <FONT COLOR="[dark_color]"><B>heslo</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	  <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="previous_action" VALUE="subrequest">
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_subscribe" VALUE="P�ihl�sit se">
        </FORM>
Toto heslo, spojen� s Va�� emailovou adresou, V�m umo�n� p��stup k Va�em
vlastn�mu prost�ed�.

  [ELSIF status=notauth_noemail]

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>Va�e emailov� adresa</B> </FONT>
	  <INPUT  NAME="email" SIZE="30"><BR>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="action" VALUE="subrequest">
	  <INPUT TYPE="submit" NAME="action_subrequest" VALUE="Odeslat">
         </FORM>

  [ELSIF status=notauth]

         Pro potvrzen� Va�eho p�ihl�en� do konference [list], vlo�te Va�e heslo:

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>emailov� adresa</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>heslo</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	  <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="previous_action" VALUE="subrequest">
         &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_subscribe" VALUE="P�ihl�sit se">
	<INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="Moje heslo ?">
         </FORM>

  [ELSIF status=notauth_subscriber]

	<FONT COLOR="[dark_color]"><B>Jste ji� �lenem konference [list].
	</FONT>
	<BR><BR>


	[PARSE '--ETCBINDIR--/wws_templates/loginbanner.cz.tpl']

  [ENDIF]      



