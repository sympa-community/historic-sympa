<!-- RCS Identication ; $Revision$ ; $Date$ -->

      �z�ѰO�F�K�X�A�Ϊ̱z�q�ӨS����o�o�� Server �W�� Mailing List �K�X<BR>
      �K�X�N�q�L�q�l�l��o�e���z:

      <FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="referer" VALUE="[referer]">
        <B>�z���q�l�l��a�}</B>: <BR>
	  <INPUT TYPE="hidden" NAME="action" VALUE="sendpasswd">
	  <INPUT TYPE="hidden" NAME="nomenu" VALUE="[nomenu]">

        [IF email]
	  [email]
          <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	[ELSE]
	  <INPUT TYPE="text" NAME="email" SIZE="20">
	[ENDIF]
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="���ڵo�e�K�X">
      </FORM>
