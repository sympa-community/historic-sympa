<!-- RCS Identication ; $Revision$ ; $Date$ -->

  <FORM ACTION="[path_cgi]" METHOD=POST>

  您於<FONT COLOR="[dark_color]">[subscriber->date]</FONT>其開始訂閱  <BR><BR>
     <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
     接收模式: 
     <SELECT NAME="reception">
        [FOREACH r IN reception]
          <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
        [END]
     </SELECT>

     [PARSE '/usr/local/sympa/bin/etc/wws_templates/button_header.tpl']
     <TD NOWRAP BGCOLOR="[light_color]" ALIGN="center"> 
      <A HREF="[path_cgi]/nomenu/help/user_options" onClick="window.open('','wws_help','toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes,copyhistory=no,width=400,height=200')" TARGET="wws_help">
     <FONT SIZE=-1><B>幫助</B></FONT></A>
     </TD>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/button_footer.tpl']

     <BR>可見性:
     <SELECT NAME="visibility">
        [FOREACH r IN visibility]
          <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
        [END]
     </SELECT>

     <BR>
     <INPUT TYPE="submit" NAME="action_set" VALUE="更新">
     
</FORM>
