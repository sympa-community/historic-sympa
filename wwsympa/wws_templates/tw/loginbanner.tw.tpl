<!-- RCS Identication ; $Revision$ ; $Date$ -->
<BR>
[IF password_sent]
  �z���K�X�w�g�Q�o�e��z�� Email �a�} [init_email]�C<BR>
  ���ˬd�z�� Email �l��c���o�z���K�X�A�b���U��J�C<BR><BR>
[ENDIF]

[IF action=loginrequest]
 �z�ݭn Login �Өϥαz�ۭq�� WWSympa ���ҡA�ζi��@�� Privilege �ާ@(�ݭn�z�� email �a�})�C
[ELSE]
 �j�h�ƪ� Mailing List �S�ʻݭn�z�� email �a�}�C�Y�� Mailing List ���|�Q���g�T�{���H�ݨ�C<BR>
 �p�G�Q�n��o�� Server ���Ѫ��������A�ȡA�z�i��ݭn�����T�{�z�ۤv�������C<BR>
[ENDIF]

    <FORM ACTION="[path_cgi]" METHOD=POST> 
        <INPUT TYPE="hidden" NAME="previous_action" VALUE="[previous_action]">
        <INPUT TYPE="hidden" NAME="previous_list" VALUE="[previous_list]">
	<INPUT TYPE="hidden" NAME="referer" VALUE="[referer]">
	<INPUT TYPE="hidden" NAME="action" VALUE="login">
	<INPUT TYPE="hidden" NAME="nomenu" VALUE="[nomenu]">

        <TABLE BORDER=0 width=100% CELLSPACING=0 CELLPADDING=0>
         <TR BGCOLOR="[light_color]">
          <TD NOWRAP align=center>
     	      <INPUT TYPE=hidden NAME=list VALUE="[list]">
     	      <FONT SIZE=-1 COLOR="[selected_color]"><b>�l��a�}: <INPUT TYPE=text NAME=email SIZE=20 VALUE="[init_email]">
      	      �K�X: </b>
              <INPUT TYPE=password NAME=passwd SIZE=8>&nbsp;&nbsp;
              <INPUT TYPE="submit" NAME="action_login" VALUE=" Login " SELECTED>
   	    </TD>
     	  </TR>
       </TABLE>
 </FORM> 

<CENTER>

    <B>�l��a�}</B>�A�O�z���q�\ email �a�}<BR>
    <B>�K�X</B>�A�O�z���K�X�C<BR><BR>

<TABLE border=0><TR>
<TD>
<I>�p�G�z�S���q Server ��o�L�K�X�αz�ѰO�F�K�X: </I>
</TD><TD>
<TABLE CELLPADDING="2" CELLSPACING="2" WIDTH="100%" BORDER="0">
  <TR ALIGN=center BGCOLOR="[dark_color]">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="[light_color]" ALIGN="center"> 
      [IF escaped_init_email]
         <A HREF="[path_cgi]/nomenu/sendpasswd/[escaped_init_email]"
      [ELSE]
         <A HREF="[path_cgi]/nomenu/remindpasswd/referer/[referer]"
      [ENDIF]
       onClick="window.open('','wws_login','toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes,copyhistory=no,width=450,height=300')" TARGET="wws_login">
     <FONT SIZE=-1><B>���ڵo�e�K�X</B></FONT></A>
     </TD>
    </TR>
  </TABLE>
</TR>
</TABLE>
</TD></TR></TABLE>
</CENTER>




