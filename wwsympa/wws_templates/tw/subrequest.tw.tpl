<!-- RCS Identication ; $Revision$ ; $Date$ -->

  [IF status=auth]

	您請求訂閱 Mailing List  [list]。<BR>要確認您的請求，請點擊下面的按鈕: <BR>
	<BR>

	<FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[user->email]">
	  <INPUT TYPE="submit" NAME="action_subscribe" VALUE="我訂閱 Mailing List  [list]">
	</FORM>

  [ELSIF status=notauth_passwordsent]

    	您請求訂閱 Mailing List  [list]。
	<BR><BR>
	為了確認您的身份，避免其他人違背您的意願為您訂閱這個 Mailing List ，將發送一個包含
	您的密碼的郵件給您。<BR><BR>

	檢查您的郵件箱，然後在下面輸入密碼。這將確認您訂閱 Mailing List  [list]。
	
        <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>e-mail address</B> </FONT>[email]<BR>
	  <FONT COLOR="[dark_color]"><B>密碼</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	  <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="previous_action" VALUE="subrequest">
        &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_subscribe" VALUE="訂閱">
        </FORM>

      	這個密碼，和您的郵件地址關聯，允許您訪問自己的自訂環境。

  [ELSIF status=notauth_noemail]

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>您的電子郵件地址</B> 
	  <INPUT  NAME="email" SIZE="30"><BR>
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="action" VALUE="subrequest">
	  <INPUT TYPE="submit" NAME="action_subrequest" VALUE="確認">
         </FORM>


  [ELSIF status=notauth]

	為了確認您訂閱 Mailing List  [list]，請在下面輸入您的密碼:

         <FORM ACTION="[path_cgi]" METHOD=POST>
          <FONT COLOR="[dark_color]"><B>電子郵件地址</B> </FONT>[email]<BR>
            <FONT COLOR="[dark_color]"><B>密碼</B> </FONT> 
  	  <INPUT TYPE="password" NAME="passwd" SIZE="20">
	  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="email" VALUE="[email]">
	  <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
	  <INPUT TYPE="hidden" NAME="previous_action" VALUE="subrequest">
         &nbsp; &nbsp; &nbsp;<INPUT TYPE="submit" NAME="action_subscribe" VALUE="訂閱">
	<INPUT TYPE="submit" NAME="action_sendpasswd" VALUE="我的密碼 ?">
         </FORM>

  [ELSIF status=notauth_subscriber]

	<FONT COLOR="[dark_color]"><B>您已經訂閱了 Mailing List  [list]。
	</FONT>
	<BR><BR>


	[PARSE '/usr/local/sympa/bin/etc/wws_templates/loginbanner.tw.tpl']

  [ENDIF]      



