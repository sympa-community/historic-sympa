<!-- RCS Identication ; $Revision$ ; $Date$ -->

    <TABLE WIDTH="100%" BORDER=0 CELLPADDING=10>
      <TR VALIGN="top">
        <TD NOWRAP>
	  <FORM ACTION="[path_cgi]" METHOD=POST>
	    <FONT COLOR="[dark_color]"><B>�]�m�w�] Mailing List  Template </B></FONT><BR>
	     <SELECT NAME="file">
	      [FOREACH f IN lists_default_files]
	        <OPTION VALUE='[f->NAME]' [f->selected]>[f->complete]
	      [END]
	    </SELECT>
	    <INPUT TYPE="submit" NAME="action_editfile" VALUE="�s��">
	  </FORM>

	  <FORM ACTION="[path_cgi]" METHOD=POST>
	    <FONT COLOR="[dark_color]"><B>�]�m���I Template </B></FONT><BR>
	     <SELECT NAME="file">
	      [FOREACH f IN server_files]
	        <OPTION VALUE='[f->NAME]' [f->selected]>[f->complete]
	      [END]
	    </SELECT>
	    <INPUT TYPE="submit" NAME="action_editfile" VALUE="�s��">
	  </FORM>
	</TD>
      </TR>

      <TR><TD>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/button_header.tpl']
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
      <A HREF="[path_cgi]/get_pending_lists">��C���� Mailing List </A>
       </TD>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/button_footer.tpl']

    </TD></TR>

      <TR><TD NOWRAP>
        <FORM ACTION="[path_cgi]" METHOD="POST">
	  <INPUT NAME="email" SIZE="30" VALUE="[email]">
	  <INPUT TYPE="hidden" NAME="action" VALUE="search_user">
	  <INPUT TYPE="submit" NAME="action_search_user" VALUE="�d�ߨϥΪ�">
	</FORM>     
      </TD></TR>

      <TR><TD>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/button_header.tpl']
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
        <A HREF="[path_cgi]/view_translations">�ۭq�Ҷ�</A>
       </TD>
      [PARSE '/usr/local/sympa/bin/etc/wws_templates/button_footer.tpl']
      </TD></TR>

      <TR>
        <TD>
<FONT COLOR="[dark_color]">�ϥ�<CODE>arctxt</CODE>�ؿ��@����J<B>���� HTML �k��</B>�C
        </TD>
      </TR>
      <TR>
        <TD>
          <FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="submit" NAME="action_rebuildallarc" VALUE="����"><BR>
	�i��n���Ϋܤj�� CPU �ɶ��A�p�ߨϥ�!
          </FORM>
	</TD>

    <TD ALIGN="CENTER"> 
          <FORM ACTION="[path_cgi]" METHOD=POST>
	  <INPUT TYPE="text" NAME="list" SIZE="20">
          <INPUT TYPE="submit" NAME="action_rebuildarc" VALUE="�����k��">
          </FORM>
    </TD>


      </TR>

      <TR>
        <TD>
	  <FONT COLOR="[dark_color]">
	  <A HREF="[path_cgi]/scenario_test">
	     <b>�������ռҶ�</b>
          </A>
          </FONT>
	</TD>
      </TR>
	
    </TABLE>


