<!-- RCS Identication ; $Revision$ ; $Date$ -->

  [IF status=auth]
      您請求退訂 Mailing List  [list]。<BR>要確認您的請求，請點下面的按鈕:<BR>
	<BR>

	<FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[user->email]">
	  <INPUT TYPE="submit" NAME="action_signoff" VALUE="我退訂 Mailing List  [list]">
	</FORM>

  [ELSIF not_subscriber]

      您沒有用郵件地址 [email] 訂閱 Mailing List  [list]。
      <BR><BR>
      您可能使用其它的郵件地址訂閱的 Mailing List 。
      請聯系 Mailing List 所有者來幫助您退訂:
      <A HREF="mailto:[list]-request@[conf->host]">[list]-request@[conf->host]</A>
      
  [ELSIF init_passwd]
        您請求退訂 Mailing List  [list]。
	<BR><BR>
	為了確認您的身份，避免其他人違背您的意願將您從這個 Mailing List 中退訂，將發送
	一個包含 URL 的郵件給您。<BR><BR>

	檢查您的郵件箱，然後在下面輸入 Sympa 發送給您的郵件中的密碼。這將
	確認您退訂 Mailing List  [list]。
	
        <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>e-mail address</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>密碼</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_signoff" VALUE="退訂">
        </FORM>

      	這個密碼，和您的郵件地址關聯，允許您訪問自己的自訂環境。

  [ELSIF ! email]
      請給出退訂 Mailing List  [list] 所用的郵件地址。

      <FORM ACTION="[path_cgi]" METHOD=POST>
          <B>您的郵件地址: </B> 
          <INPUT NAME="email"><BR>
          <INPUT TYPE="hidden" NAME="action" VALUE="sigrequest">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="submit" NAME="action_sigrequest" VALUE="退訂">
         </FORM>


  [ELSE]

	為了確認您退訂 Mailing List  [list]，請在下面輸入您的密碼:

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>e-mail address</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>密碼</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
         &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_signoff" VALUE="退訂">

<BR><BR>
<I>如果您從來沒有從 Server 獲得過密碼，或者您忘記了密碼: </I>  <INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="給我發送密碼">

         </FORM>

  [ENDIF]      













