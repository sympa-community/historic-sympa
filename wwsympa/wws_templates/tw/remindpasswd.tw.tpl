<!-- RCS Identication ; $Revision$ ; $Date$ -->

      您忘記了密碼，或者您從來沒有獲得這個 Server 上的 Mailing List 密碼<BR>
      密碼將通過電子郵件發送給您:

      <FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="referer" VALUE="[referer]">
        <B>您的電子郵件地址</B>: <BR>
	  <INPUT TYPE="hidden" NAME="action" VALUE="sendpasswd">
	  <INPUT TYPE="hidden" NAME="nomenu" VALUE="[nomenu]">

        [IF email]
	  [email]
          <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	[ELSE]
	  <INPUT TYPE="text" NAME="email" SIZE="20">
	[ENDIF]
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="給我發送密碼">
      </FORM>
