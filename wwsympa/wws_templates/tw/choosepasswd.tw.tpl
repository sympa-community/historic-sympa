<!-- RCS Identication ; $Revision$ ; $Date$ -->

�z�ݭn���z�� WWSympa ���ҿ�ܤ@�ӱK�X�C
�z�ݭn�γo�ӱK�X�Өϥ�Privilege�S�ʡC

<FORM ACTION="[path_cgi]" METHOD=POST>
<INPUT TYPE="hidden" NAME="previous_action" VALUE="[previous_action]">
<INPUT TYPE="hidden" NAME="previous_list" VALUE="[previous_list]">

[IF init_passwd]
  <INPUT TYPE="hidden" NAME="passwd" VALUE="[user->password]">
[ELSE]
  <FONT COLOR="[dark_color]">��e�K�X: </FONT>
  <INPUT TYPE="password" NAME="passwd" SIZE=15>
[ENDIF]

<BR><BR><FONT COLOR="[dark_color]">�s�K�X: </FONT>
<INPUT TYPE="password" NAME="newpasswd1" SIZE=15>
<BR><BR><FONT COLOR="[dark_color]">�A����J�s�K�X: </FONT>
<INPUT TYPE="password" NAME="newpasswd2" SIZE=15>
<BR><BR><INPUT TYPE="submit" NAME="action_setpasswd" VALUE="�T�{">

</FORM>

