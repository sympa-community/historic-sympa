<!-- RCS Identication ; $Revision$ ; $Date$ -->

  [IF status=auth]

	�z�ШD�q�\ Mailing List  [list]�C<BR>�n�T�{�z���ШD�A���I���U�������s: <BR>
	<BR>

	<FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[user->email]">
	  <INPUT TYPE="submit" NAME="action_subscribe" VALUE="�ڭq�\ Mailing List  [list]">
	</FORM>

  [ELSIF status=notauth_passwordsent]

    	�z�ШD�q�\ Mailing List  [list]�C
	<BR><BR>
	���F�T�{�z�������A�קK��L�H�H�I�z���N�@���z�q�\�o�� Mailing List �A�N�o�e�@�ӥ]�t
	�z���K�X���l�󵹱z�C<BR><BR>

	�ˬd�z���l��c�A�M��b�U����J�K�X�C�o�N�T�{�z�q�\ Mailing List  [list]�C
	
        <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>e-mail address</B> </FONT>[email]<BR>
	  <FONT COLOR="[dark_color]"><B>�K�X</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	  <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="previous_action" VALUE="subrequest">
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_subscribe" VALUE="�q�\">
        </FORM>

      	�o�ӱK�X�A�M�z���l��a�}���p�A���\�z�X�ݦۤv���ۭq���ҡC

  [ELSIF status=notauth_noemail]

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>�z���q�l�l��a�}</B> 
	  <INPUT  NAME="email" SIZE="30"><BR>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="action" VALUE="subrequest">
	  <INPUT TYPE="submit" NAME="action_subrequest" VALUE="�T�{">
         </FORM>


  [ELSIF status=notauth]

	���F�T�{�z�q�\ Mailing List  [list]�A�Цb�U����J�z���K�X:

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>�q�l�l��a�}</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>�K�X</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	  <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="previous_action" VALUE="subrequest">
         &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_subscribe" VALUE="�q�\">
	<INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="�ڪ��K�X ?">
         </FORM>

  [ELSIF status=notauth_subscriber]

	<FONT COLOR="[dark_color]"><B>�z�w�g�q�\�F Mailing List  [list]�C
	</FONT>
	<BR><BR>


	[PARSE '/usr/local/sympa/bin/etc/wws_templates/loginbanner.tw.tpl']

  [ENDIF]      



