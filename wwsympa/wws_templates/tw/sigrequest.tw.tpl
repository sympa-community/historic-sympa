<!-- RCS Identication ; $Revision$ ; $Date$ -->

  [IF status=auth]
      �z�ШD�h�q Mailing List  [list]�C<BR>�n�T�{�z���ШD�A���I�U�������s:<BR>
	<BR>

	<FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[user->email]">
	  <INPUT TYPE="submit" NAME="action_signoff" VALUE="�ڰh�q Mailing List  [list]">
	</FORM>

  [ELSIF not_subscriber]

      �z�S���ζl��a�} [email] �q�\ Mailing List  [list]�C
      <BR><BR>
      �z�i��ϥΨ䥦���l��a�}�q�\�� Mailing List �C
      ���p�t Mailing List �Ҧ��̨����U�z�h�q:
      <A HREF="mailto:[list]-request@[conf->host]">[list]-request@[conf->host]</A>
      
  [ELSIF init_passwd]
        �z�ШD�h�q Mailing List  [list]�C
	<BR><BR>
	���F�T�{�z�������A�קK��L�H�H�I�z���N�@�N�z�q�o�� Mailing List ���h�q�A�N�o�e
	�@�ӥ]�t URL ���l�󵹱z�C<BR><BR>

	�ˬd�z���l��c�A�M��b�U����J Sympa �o�e���z���l�󤤪��K�X�C�o�N
	�T�{�z�h�q Mailing List  [list]�C
	
        <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>e-mail address</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>�K�X</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_signoff" VALUE="�h�q">
        </FORM>

      	�o�ӱK�X�A�M�z���l��a�}���p�A���\�z�X�ݦۤv���ۭq���ҡC

  [ELSIF ! email]
      �е��X�h�q Mailing List  [list] �ҥΪ��l��a�}�C

      <FORM ACTION="[path_cgi]" METHOD=POST>
          <B>�z���l��a�}: </B> 
          <INPUT NAME="email"><BR>
          <INPUT TYPE="hidden" NAME="action" VALUE="sigrequest">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="submit" NAME="action_sigrequest" VALUE="�h�q">
         </FORM>


  [ELSE]

	���F�T�{�z�h�q Mailing List  [list]�A�Цb�U����J�z���K�X:

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>e-mail address</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>�K�X</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
         &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_signoff" VALUE="�h�q">

<BR><BR>
<I>�p�G�z�q�ӨS���q Server ��o�L�K�X�A�Ϊ̱z�ѰO�F�K�X: </I>  <INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="���ڵo�e�K�X">

         </FORM>

  [ENDIF]      













