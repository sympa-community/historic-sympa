<!-- RCS Identication ; $Revision$ ; $Date$ -->

<!-- begin list_menu.tpl -->
<TABLE border="0"  CELLPADDING="0" CELLSPACING="0">
 <TR VALIGN="top"><!-- empty line in the left menu panel -->
  <TD WIDTH="5" BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="40" BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="30" ></TD>
  <TD WIDTH="40" ></TD>
 </TR>
 <TR>
  <TD WIDTH="5" BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>

<!-- begin -->
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']

      [IF action=info]
        <TD WIDTH=100% BGCOLOR="[selected_color]" NOWRAP align=right>
           <font color="[bg_color]" size=-1><b> Mailing List 訊息</b></font>
        </TD>
      [ELSE]
        <TD WIDTH=100% BGCOLOR="[light_color]" NOWRAP align=right>
        <A HREF="[path_cgi]/info/[list]" ><font size=-1><b> Mailing List 訊息</b>
        </font></A>
        </TD>
      [ENDIF]

     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>


  <TD WIDTH=40></TD>
 </TR>
 <TR><!-- empty line in the left menu panel -->
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
 <TR><!-- Panel list info -->
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=110 COLSPAN=3 BGCOLOR="[bg_color]" NOWRAP align=left>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
        <TD BGCOLOR="[light_color]">
	  訂閱: 共 <B>[total]</B> 人<BR>
	  <BR>
	  所有者:
	  [FOREACH o IN owner]
	    <BR><FONT SIZE=-1><A HREF="mailto:[o->NAME]">[o->gecos]</A></FONT>
	  [END]
	  <BR>
	  [IF is_moderated]
	    監管者:
	    [FOREACH e IN editor]
	      <BR><FONT SIZE=-1><A HREF="mailto:[e->NAME]">[e->gecos]</A></FONT>
	    [END]
	  [ENDIF]
          <BR>
	  [IF list_as_x509_cert]
          <BR><A HREF="[path_cgi]/load_cert/[list]"><font size="-1"><b>載入憑証<b></font></A><BR>
          [ENDIF]
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>
 </TR>
 <TR><!-- empty line in the left menu panel -->
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
   [IF is_priv]
 <TR><!-- for listmaster owner and editor -->
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>

  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']

   [IF action=admin]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right><font color="[bg_color]" size=-1><b> Mailing List 管理</b></font></TD>
   [ELSIF action_type=admin]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right>
        <b>
         <A HREF="[path_cgi]/admin/[list]" ><FONT COLOR="[bg_color]" SIZE="-1"> Mailing List 管理</FONT></A>
        </b>
        </TD>
   [ELSE]
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
        <font size=-1><b>
         <A HREF="[path_cgi]/admin/[list]" > Mailing List 管理</A>
        </b></font>
        </TD>
   [ENDIF]

     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>

  <TD WIDTH=40></TD>
 </TR>
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
 <TR><!-- Panel admin info -->
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=110 COLSPAN=3 BGCOLOR="[bg_color]" NOWRAP align=left>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
        <TD BGCOLOR="[light_color]">
           退信率: <B>[bounce_rate]%</B><BR>
           <BR>
	   [if mod_total=0]
	   沒有郵件要監管
           [else]
	   要監管的郵件:<B> 共 [mod_total]</B>
           [endif]
	  <BR>
        </TD>
         [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>
 </TR>
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>


     <!-- end is_priv -->
   [ENDIF]
   <!-- Subscription depending on susbscriber or not, email define or not etc -->
   [IF is_subscriber=1]
    [IF may_suboptions=1]
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>

  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
      [IF action=suboptions]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right><font color="[bg_color]" size=-1><b>訂閱者選項</b></font></TD>
      [ELSE]
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
        <font size=-1><b>
         <A HREF="[path_cgi]/suboptions/[list]" >訂閱者選項</A>
        </b></font>
        </TD>
      [ENDIF]
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>

  <TD WIDTH=40>
  </TD>

 </TR>
  [ENDIF]

 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
   [IF may_signoff=1] 
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
      [IF action=signoff]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right><font color="[bg_color]" size=-1><b>退訂</b></font></TD>
      [ELSIF user->email]
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
        <font size=-1><b>
         <A HREF="[path_cgi]/signoff/[list]" onClick="request_confirm_link('[path_cgi]/signoff/[list]', '您確定要從 [list] 退訂?'); return false;">退訂</A>
        </b></font>
        </TD>
       [ELSE]
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
        <font size=-1><b>
         <A HREF="[path_cgi]/sigrequest/[list]">退訂</A>
        </b></font>
        </TD>
       [ENDIF]
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']

  </TD>

  <TD WIDTH=40></TD>
 </TR>
   [ELSE]
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
        <font size=-1 COLOR="[bg_color]"><b>Unsubscribe</b></font>
        </TD>
        <TD WIDTH=40></TD>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>
 </TR>
      <!-- end may_signoff -->
   [ENDIF]
      <!-- is_subscriber -->

   [ELSE]
      <!-- else is_subscriber -->

 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
   [IF action=subrequest]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right><font color="[bg_color]" size=-1><b>訂閱</b></font></TD>
   [ELSE]
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
    [IF may_subscribe=1]
      [IF user->email]
        <font size=-1><b>
     <A HREF="[path_cgi]/subscribe/[list]" onClick="request_confirm_link('[path_cgi]/subscribe/[list]', 'Do you really want to subscribe to list [list]?'); return false;">訂閱</A>
        </b></font>
      [ELSE]
         <font size=-1><b>
     <A HREF="[path_cgi]/subrequest/[list]">訂閱</A>
        </b></font>
      [ENDIF]
    [ELSE]
	<font size=-1 COLOR="[bg_color]"><b>訂閱</b></font>
    [ENDIF]
        </TD>
   [ENDIF]

     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>

  <TD WIDTH=40></TD>
 </TR>

   [IF may_signoff]
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']

        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
       [IF user->email]
        <font size=-1><b>
         <A HREF="[path_cgi]/signoff/[list]" onClick="request_confirm_link('[path_cgi]/signoff/[list]', '您確定要從 [list] 退訂?'); return false;">退訂</A>
        </b></font>
       [ELSE]
       <font size=-1><b>
         <A HREF="[path_cgi]/sigrequest/[list]">退訂</A>
        </b></font>
       [ENDIF]
        </TD>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>

  <TD WIDTH=40></TD>
 </TR>
   [ENDIF]

      <!-- END is_subscriber -->
   [ENDIF]
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
   [IF is_archived]
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
   [IF action=arc]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right>
          <font size=-1 COLOR="[bg_color]"><b>歸檔</b></font>
	</TD>
   [ELSIF action=arcsearch_form]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right>
          <font size=-1 COLOR="[bg_color]"><b>歸檔</b></font>
	</TD>
   [ELSIF action=arcsearch]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right>
          <font size=-1 COLOR="[bg_color]"><b>歸檔</b></font>
	</TD>
   [ELSIF action=arc_protect]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right>
          <font size=-1 COLOR="[bg_color]"><b>歸檔</b></font>
	</TD>
  [ELSE]

        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
   [IF arc_access]
        <font size=-1><b>
         <A HREF="[path_cgi]/arc/[list]" >歸檔</A>
        </b></font>
   [ELSE]
        <font size=-1 COLOR="[bg_color]"><b>歸檔</b></font>
   [ENDIF]
        </TD>
   [ENDIF]

     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>

  <TD WIDTH=40></TD>
 </TR>
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
      <!-- END is_archived -->
    [ENDIF]

 <!-- Post -->
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
   [IF action=compose_mail]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right>
          <font size=-1 COLOR="[bg_color]"><b>發表</b></font>
	</TD>
  [ELSE]

        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
   [IF may_post]
        <font size=-1><b>
         <A HREF="[path_cgi]/compose_mail/[list]" >發表</A>
        </b></font>
   [ELSE]
        <font size=-1 COLOR="[bg_color]"><b>發表</b></font>
   [ENDIF]
        </TD>
   [ENDIF]

     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>

  <TD WIDTH=40></TD>
 </TR>
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
      <!-- END post -->

    [IF shared=exist]
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp; </TD>   
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
    [IF action=d_read]
        <TD WIDTH="100%" BGCOLOR="[selected_color]" NOWRAP align=right><font color="[bg_color]" size=-1>
         <b>共享頁面</b></font>
        </TD>
    [ELSE]
      [IF may_d_read]
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
         <font size=-1><b>
         <A HREF="[path_cgi]/d_read/[list]/" >共享頁面</A>
         </b></font>
        </TD>
      [ELSE]
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
         <font size=-1 COLOR="[bg_color]"><b>共享頁面</b></font>
        </TD>
      [ENDIF]
    [ENDIF]

      [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>

       <!-- END shared --> 
  <TD WIDTH=40></TD>
 </TR> 
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
    [ENDIF]

    [IF may_review]
 <TR>
  <TD WIDTH=5 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH="70" COLSPAN="2" NOWRAP align=right>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_header.tpl']
        <TD WIDTH="100%" BGCOLOR="[light_color]" NOWRAP align=right>
         <font size=-1><b>
         <A HREF="[path_cgi]/review/[list]" >查看</A>
         </b></font>
	</TD>
     [PARSE '/usr/local/sympa/bin/etc/wws_templates/list_button_footer.tpl']
  </TD>
  <TD WIDTH=40></TD>
 </TR>
 <TR>
  <TD WIDTH=45 COLSPAN=2 BGCOLOR="[dark_color]" NOWRAP>&nbsp;</TD>
  <TD WIDTH=70 COLSPAN=2><BR></TD>
 </TR>
    [ENDIF]
</TABLE>
<!-- end list_menu.tpl -->
