<!-- RCS Identication ; $Revision$ ; $Date$ -->

<P>
<TABLE width=100% border="0" VALIGN="top">
<TR>
[IF is_owner]
<TD VALIGN="top" NOWRAP COLSPAN="3">
    <FORM ACTION="[path_cgi]" METHOD="POST">
      <INPUT TYPE="hidden" NAME="previous_action" VALUE="review">
      <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
      <INPUT TYPE="hidden" NAME="action" VALUE="add">
      <INPUT TYPE="text" NAME="email" SIZE="35">
      <INPUT TYPE="submit" NAME="action_add" VALUE="P�idat"> quiet<INPUT TYPE="checkbox" NAME="skryt�">
    </FORM>
</TD>
</TR>
<TR>
<TD ALIGN="right">
     [PARSE '--ETCBINDIR--/wws_templates/button_header.tpl']
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
         <FONT COLOR="[selected_color]" SIZE="-1">
         <A HREF="[path_cgi]/subindex/[list]" ><b>�ekaj�c� ��dosti o �lenstv�</b></A>
         </FONT>
       </TD>
     [PARSE '--ETCBINDIR--/wws_templates/button_footer.tpl']
</TD>
<TD>
     [PARSE '--ETCBINDIR--/wws_templates/button_header.tpl']
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
         <FONT COLOR="[selected_color]" SIZE="-1">
         <A HREF="[path_cgi]/add_request/[list]" ><b>V�cen�sobn� p�id�n�</b></A>
         </FONT>
       </TD>
     [PARSE '--ETCBINDIR--/wws_templates/button_footer.tpl']
</TD>

<TD>
     [PARSE '--ETCBINDIR--/wws_templates/button_header.tpl']
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
         <FONT COLOR="[selected_color]" SIZE="-1">

         <A HREF="[path_cgi]/remind/[list]" onClick="request_confirm_link('[path_cgi]/remind/[list]', 'Chcete opravdu poslat p�ipom�nac� zpr�vu k [total] �len�m?'); return false;"><b>Upomenout �leny</b></A>

         </FONT>
       </TD>
     [PARSE '--ETCBINDIR--/wws_templates/button_footer.tpl']
</TD>

[ENDIF]
</TR>
<TR>
<TD VALIGN="top" NOWRAP>
<FORM ACTION="[path_cgi]" METHOD="POST"> 
<INPUT TYPE="hidden" NAME="previous_action" VALUE="review">
<INPUT TYPE=hidden NAME=list VALUE="[list]">
<INPUT TYPE="hidden" NAME="action" VALUE="search">
<INPUT SIZE="18" NAME=filter VALUE="[filter]">
<INPUT TYPE="submit" NAME="action_search" VALUE="Hledat">
[IF action=search]
<BR>nalezeno [occurrence] v�skyt(�)<BR>
[IF too_many_select]
V�b�r p��li� rozs�hl�, nelze jej zobrazit
[ENDIF]
[ENDIF]
</FORM>
</TD>
</TR>
</TABLE>
<FORM NAME="myform" ACTION="[path_cgi]" METHOD="POST">
 <INPUT TYPE="hidden" NAME="previous_action" VALUE="[action]">
 <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
 <INPUT TYPE=hidden NAME=list VALUE="[list]">

<TABLE WIDTH="100%" BORDER="0">
  <TR><TD ALIGN="left" NOWRAP>
  [IF is_owner]

    <!--INPUT TYPE="button" NAME="action_del" VALUE="Delete selected email addresses" onClick="return request_confirm('Do you really want to unsubscribe ALL selected subscribers ?')"-->

    <INPUT TYPE="submit" NAME="action_del" VALUE="Smazat ozna�en� adresy">

    <INPUT TYPE="checkbox" NAME="quiet"> skryt�
  [ENDIF]
  </TD>
  <TD WIDTH="100%">&nbsp;</TD>
  [IF action<>search]
  <TD NOWRAP>
	<INPUT TYPE="hidden" NAME="sortby" VALUE="[sortby]">

	<INPUT TYPE="submit" NAME="action_review" VALUE="Velikost">

	        <SELECT NAME="size">
                  <OPTION VALUE="[size]" SELECTED>[size]
		  <OPTION VALUE="25">25
		  <OPTION VALUE="50">50
		  <OPTION VALUE="100">100
		   <OPTION VALUE="500">500
		</SELECT>
   </TD>
   <TD>
   [IF prev_page]
    <A HREF="[path_cgi]/review/[list]/[prev_page]/[size]/[sortby]"><IMG SRC="[icons_url]/left.png" BORDER=0 ALT="P�edchoz� strana"></A>
   [ENDIF]
   [IF page]
     strana [page] z [total_page]
   [ENDIF]
   [IF next_page]
     <A HREF="[path_cgi]/review/[list]/[next_page]/[size]/[sortby]"><IMG SRC="[icons_url]/right.png" BORDER="0" ALT="Dal�� strana"></A>
   [ENDIF]
  [ENDIF]
  </TD></TR>
  </TABLE>

    <TABLE WIDTH="100%" BORDER="1">
      <TR BGCOLOR="[light_color]">
	[IF is_owner]
	   <TH><FONT SIZE="-1"><B>X</B></FONT></TH>
	[ENDIF]
        [IF sortby=email]
  	    <TH NOWRAP COLSPAN=2 BGCOLOR="[selected_color]">
	    <FONT COLOR="[bg_color]" SIZE="-1"><b>Emailov� adresa</b></FONT>
	[ELSE]
	    <TH NOWRAP COLSPAN=2>
	    <A HREF="[path_cgi]/review/[list]/1/[size]/email" >
	    <FONT SIZE="-1"><b>Emailov� adresa</b></A>
	[ENDIF]
	</TH>
        [IF sortby=domain]
  	    <TH NOWRAP BGCOLOR="[selected_color]">
	    <FONT COLOR="[bg_color]" SIZE="-1"><b>Dom�na</b></FONT>
	[ELSE]
	    <TH NOWRAP>
	    <A HREF="[path_cgi]/review/[list]/1/[size]/domain" >
	    <FONT SIZE="-1"><b>Dom�na</b></FONT></A>
	[ENDIF]
	</TH>
	[IF sortby=name]
	<TH NOWRAP BGCOLOR="[selected_color]">
	  <FONT COLOR="[bg_color]" SIZE="-1">Jm�no</FONT>
	[ELSE]
	<TH NOWRAP>
		<A HREF="[path_cgi]/review/[list]/1/[size]/name">
		<FONT SIZE="-1">Jm�no</FONT></a>
	[ENDIF] 
	</TH>
        [IF is_owner]
	  <TH><FONT SIZE="-1"><B>Zp�sob p�ij�m�n�</B></FONT>
	  </TH>
	  [IF list_conf->user_data_source=include2]
         [IF sortby=sources]
  	    <TH NOWRAP BGCOLOR="[selected_color]">
	    <FONT COLOR="[bg_color]" SIZE="-1"><b>Zdroje</b></FONT>
	[ELSE]
	    <TH NOWRAP>
	    <A HREF="[path_cgi]/review/[list]/1/[size]/sources" >
	    <FONT SIZE="-1"><b>Zdroje</b></FONT></A>
	[ENDIF]
	  </TH>
          [ENDIF]
	  [IF sortby=date]
  	    <TH NOWRAP BGCOLOR="[selected_color]">
	    <FONT COLOR="[bg_color]" SIZE="-1"><b>Datum p�ihl�en�</b></FONT>
	  [ELSE]
	    <TH NOWRAP><FONT SIZE="-1">
	    <A HREF="[path_cgi]/review/[list]/1/[size]/date" >
	    <b>Datum p�ihl�en�</b></A></FONT>
	  [ENDIF]
          </TH>
	  <TH><FONT SIZE="-1"><B>Posledn� zm�na</B></FONT></TH>
	  [IF additional_fields]
	  <TH><FONT SIZE="-1"><B>[additional_fields]</B></FONT></TH>
	  [ENDIF]
        [ENDIF]
      </TR>
      
      [FOREACH u IN members]
	[IF dark=1]
	  <TR BGCOLOR="[shaded_color]" VALIGN="top">
	[ELSE]
          <TR BGCOLOR="[bg_color]" VALIGN="top">
	[ENDIF]

	 [IF is_owner]
	  [IF u->subscribed]
	    <TD>
	        <INPUT TYPE=checkbox name="email" value="[u->escaped_email]">
	    </TD>
	  [ELSE]
            <TD>&nbsp;</TD>
          [ENDIF]
	 [ENDIF]
	 [IF u->bounce]
	  <TD COLSPAN=2 NOWRAP><FONT SIZE=-1>
	 
	      [IF is_owner]
		<A HREF="[path_cgi]/editsubscriber/[list]/[u->escaped_email]/review">[u->email]</A>
	      [ELSE]
 	        [u->email]
 	      [ENDIF]
	  </FONT></TD>
            <TD ALIGN="right"BGCOLOR="[error_color]"><FONT SIZE=-1 COLOR="[bg_color]"><B>vracej�c� se zpr�vy</B></FONT>
	    </TD>

	 [ELSE]
	  <TD COLSPAN=3 NOWRAP><FONT SIZE=-1>
	      [IF is_owner]
		<A HREF="[path_cgi]/editsubscriber/[list]/[u->escaped_email]/review">[u->email]</A>
	      [ELSE]
	        [u->email]
	      [ENDIF]
	  </FONT></TD>
	 [ENDIF]

	  <TD>
             <FONT SIZE=-1>
	        [u->gecos]&nbsp;
	     </FONT>
          </TD>
	  [IF is_owner]
  	    <TD ALIGN="center"><FONT SIZE=-1>
  	      [u->reception]
	    </FONT></TD>
          [IF list_conf->user_data_source=include2]
            <TD ALIGN="left"><FONT SIZE=-1>
            [IF u->subscribed]
              [IF u->included]
                 p��hl�en<BR>[u->sources]
              [ELSE]
                 p��hl�en
              [ENDIF]
            [ELSE]
              [u->sources]
            [ENDIF]   
            </FONT></TD>
          [ENDIF]
	    <TD ALIGN="center"NOWRAP><FONT SIZE=-1>
	      [u->date]
	    </FONT></TD>
	    <TD ALIGN="center"NOWRAP><FONT SIZE=-1>
	      [u->update_date]
	    </FONT></TD>
    	  [IF additional_fields]
	     <TD ALIGN="center"NOWRAP><FONT SIZE=-1>
	      [u->additional]
	    </FONT></TD>
	  [ENDIF]
       	  [ENDIF]
        </TR>

        [IF dark=1]
	  [SET dark=0]
	[ELSE]
	  [SET dark=1]
	[ENDIF]

        [END]


      </TABLE>
    <TABLE WIDTH=100% BORDER=0>
    <TR><TD ALIGN="left">
      [IF is_owner]

        <!--INPUT TYPE="button" NAME="action_del" VALUE="Smazat ozna�en� adresy" onClick="return request_confirm('Opravdu chcete odhl�sit V�ECHNY vybran� �leny?')"-->

	<INPUT TYPE="submit" NAME="action_del" VALUE="Smazat ozna�en� adresy">

        <INPUT TYPE="checkbox" NAME="quiet"> skryt�
      [ENDIF]
    </TD>

   [IF action<>search]
    <TD ALIGN="right">
       [IF prev_page]
	 <A HREF="[path_cgi]/review/[list]/[prev_page]/[size]/[sortby]"><IMG SRC="[icons_url]/left.png" BORDER=0 ALT="P�edchoz� strana"></A>
       [ENDIF]
       [IF page]
     strana [page] z [total_page] 
       [ENDIF]
       [IF next_page]
	  <A HREF="[path_cgi]/review/[list]/[next_page]/[size]/[sortby]"><IMG SRC="[icons_url]/right.png" BORDER=0 ALT="Dal�� strana"></A>
       [ENDIF]
    </TD>
   [ENDIF]
    </TR>
    [IF is_owner]
    <TR><TD><input type=button value="Obr�tit v�b�r" onClick="toggle_selection(document.myform.email)">
    </TD></TR>
    [ENDIF]
    </TABLE>
    </FORM>






