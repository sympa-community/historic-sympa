<!-- RCS Identication ; $Revision$ ; $Date$ -->
<BR>
[IF password_sent]
  您的密碼已經被發送到您的 Email 地址 [init_email]。<BR>
  請檢查您的 Email 郵件箱取得您的密碼，在底下輸入。<BR><BR>
[ENDIF]

[IF action=loginrequest]
 您需要 Login 來使用您自訂的 WWSympa 環境，或進行一個 Privilege 操作(需要您的 email 地址)。
[ELSE]
 大多數的 Mailing List 特性需要您的 email 地址。某些 Mailing List 不會被未經確認的人看到。<BR>
 如果想要獲得本 Server 提供的完全的服務，您可能需要首先確認您自己的身份。<BR>
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
     	      <FONT SIZE=-1 COLOR="[selected_color]"><b>郵件地址: <INPUT TYPE=text NAME=email SIZE=20 VALUE="[init_email]">
      	      密碼: </b>
              <INPUT TYPE=password NAME=passwd SIZE=8>&nbsp;&nbsp;
              <INPUT TYPE="submit" NAME="action_login" VALUE=" Login " SELECTED>
   	    </TD>
     	  </TR>
       </TABLE>
 </FORM> 

<CENTER>

    <B>郵件地址</B>，是您的訂閱 email 地址<BR>
    <B>密碼</B>，是您的密碼。<BR><BR>

<TABLE border=0><TR>
<TD>
<I>如果您沒有從 Server 獲得過密碼或您忘記了密碼: </I>
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
     <FONT SIZE=-1><B>給我發送密碼</B></FONT></A>
     </TD>
    </TR>
  </TABLE>
</TR>
</TABLE>
</TD></TR></TABLE>
</CENTER>




