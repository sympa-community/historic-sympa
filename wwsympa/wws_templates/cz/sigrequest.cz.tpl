<!-- RCS Identication ; $Revision$ ; $Date$ -->

  [IF status=auth]
Po�adujete odhl�en� z konference [list]. <BR>Pro potvrzen� Va�eho po�adavku
Stiskn�te tla��tko dole :<BR>
	<BR>

	<FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[user->email]">
	  <INPUT TYPE="submit" NAME="action_signoff" VALUE="Odhla�uji se z konference [list]">
	</FORM>

  [ELSIF not_subscriber]

      Nejste �lenem konference [list] s adresou [email].
      <BR><BR>
Mo�n� jste p�ihl�en z jin� adresy. Kontaktujte pros�m spr�vce konference, aby
V�m pomohl s odhl�en�m:
 <A HREF="mailto:[list]-request@[conf->host]">[list]-request@[conf->host]</A>
      
  [ELSIF init_passwd]
Po�adujete odhl�en� z konference [list]. 
	<BR><BR>
Pro potvrzen� Va�� identity a abychom zabr�nili ciz�m osob�m ve Va�em odhl�en�
proti Va�� v�li, bude V�m odesl�na zpr�va s odkazem. <BR><BR>

Zkontrolujte si Va�i schr�nku a vlo�te dole heslo, kter� je v dan� zpr�v�.
T�mto potvrd�te Va�e odhl�en� z konference [list].
	
        <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>emailov� adresa</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>heslo</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_signoff" VALUE="Odhl�sit">
        </FORM>
Toto heslo, p�ipojen� k Va�� adrese, V�m zp��stupn� Va�e vlastn� prost�ed�.

  [ELSIF ! email]
Pros�m, napi�te Va�i adresu pro odhl�en� se z konference [list].

      <FORM ACTION="[path_cgi]" METHOD=POST>
          <B>Va�e emailov� adresa:</B> 
          <INPUT NAME="email"><BR>
          <INPUT TYPE="hidden" NAME="action" VALUE="sigrequest">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="submit" NAME="action_sigrequest" VALUE="Odhl�sit">
         </FORM>


  [ELSE]

Pro potvrzen� va�eho po�adavku na odhl�en� z konference [list], vlo�te Va�e
heslo :

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>emailov� adresa</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>heslo</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
         &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_signoff" VALUE="Odhl�sit">

<BR><BR> 
<I>Pokud zde nem�te heslo, nebo si ho nepamatujete :</I>  
<INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="Za�lete mi heslo">
         </FORM>

  [ENDIF]      
