
      Usted no tiene una contrase�a en este servidor o se le ha olvidado<br>
      Se le ser� enviada por email :

      <FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="referer" VALUE="[referer]">
	  <INPUT TYPE="hidden" NAME="action" VALUE="sendpasswd">
        <FONT COLOR="--DARK_COLOR--"><B>Direcci�n E-mail</B> </FONT>
        [IF email]
	  [email]
          <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	[ELSE]
	  <INPUT TYPE="text" NAME="email" SIZE="20">
	[ENDIF]
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="Enviarme mi contrase�a">
      </FORM>
