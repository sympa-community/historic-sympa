<!-- RCS Identication ; $Revision$ ; $Date$ -->
<P>
<TABLE width=100% border="0" VALIGN="top">
<TR>
[IF is_owner]
<TD VALIGN="top" NOWRAP>
    <FORM ACTION="[path_cgi]" METHOD="POST">
      <INPUT TYPE="hidden" NAME="previous_action" VALUE="review">
      <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
      <INPUT TYPE="hidden" NAME="action" VALUE="add">
      <INPUT TYPE="text" NAME="email" SIZE="18">
      <INPUT TYPE="submit" NAME="action_add" VALUE="�s�W> �w�R<INPUT TYPE="checkbox" NAME="quiet">
    </FORM>
</TD>
<TD>
 <TABLE BORDER="0" CELLPADDING="1" CELLSPACING="0"><TR><TD BGCOLOR="[dark_color]" VALIGN="top">
   <TABLE BORDER="0" WIDTH="100%" CELLSPACING="1" CELLPADDING="2" VALIGN="top">
     <TR>
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
         <FONT COLOR="[selected_color]" SIZE="-1">
         <A HREF="[path_cgi]/add_request/[list]" ><b>�s�W��</b></A>
         </FONT>
       </TD>
     </TR>
   </TABLE></TD></TR>
 </TABLE>
</TD>

<TD>
 <TABLE BORDER="0" CELLPADDING="1" CELLSPACING="0"><TR><TD BGCOLOR="[dark_color]" VALIGN="top">
   <TABLE BORDER="0" WIDTH="100%" CELLSPACING="1" CELLPADDING="2" VALIGN="top">
     <TR>
       <TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
         <FONT COLOR="[selected_color]" SIZE="-1">

         <A HREF="[path_cgi]/remind/[list]" onClick="request_confirm_link('[path_cgi]/remind/[list]', '�z�T�w�n��������[total]�ӭq�\�̵o�e�q�\�����l���?'); return false;"><b>���������q�\��</b></A>

         </FONT>
       </TD>
     </TR>
   </TABLE></TD></TR>
 </TABLE>
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
<INPUT TYPE="submit" NAME="action_search" VALUE="�d��">
[IF action=search]
<BR>��� [occurrence] �ӲŦX<BR>
[IF too_many_select]
��ܽd��Ӽe�A�L�k��ܿ��
[ENDIF]
[ENDIF]
</FORM>
</TD>
</TR>
</TABLE>
<FORM ACTION="[path_cgi]" METHOD="POST">
 <INPUT TYPE="hidden" NAME="previous_action" VALUE="[action]">
 <INPUT TYPE="hidden" NAME="previous_list" VALUE="[list]">
 <INPUT TYPE=hidden NAME=list VALUE="[list]">

<TABLE WIDTH="100%" BORDER="0">
  <TR><TD ALIGN="left" NOWRAP>
  [IF is_owner]

    <!--INPUT TYPE="submit" NAME="action_del" VALUE="Delete selected email addresses" onClick="return request_confirm('Do you really want to unsubscribe ALL selected subscribers ?')"-->

    <INPUT TYPE="submit" NAME="action_del" VALUE="�R���襤���l��a�}">

    <INPUT TYPE="checkbox" NAME="quiet"> �w�R
  [ENDIF]
  </TD>
  <TD>
  <TD WIDTH="100%">&nbsp;</TD>
  [IF action<>search]
  <TD NOWRAP>
	<INPUT TYPE="hidden" NAME="sortby" VALUE="[sortby]">
	<INPUT TYPE="submit" NAME="action_review" VALUE="�����j�p">
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
    <A HREF="[path_cgi]/review/[list]/[prev_page]/[size]/[sortby]"><IMG SRC="[icons_url]/left.png" BORDER=0 ALT="�e�@��"></A>
   [ENDIF]
   [IF page]
     [page]/[total_page]
   [ENDIF]
   [IF next_page]
     <A HREF="[path_cgi]/review/[list]/[next_page]/[size]/[sortby]"><IMG SRC="[icons_url]/right.png" BORDER="0" ALT="��@��"></A>
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
	    <FONT COLOR="[bg_color]" SIZE="-1"><b>�q�l�l��</b></FONT>
	[ELSE]
	    <TH NOWRAP COLSPAN=2>
	    <A HREF="[path_cgi]/review/[list]/1/[size]/email" >
	    <FONT SIZE="-1"><b>�q�l�l��</b></A>
	[ENDIF]
	</TH>
        <TH><FONT SIZE="-1"><B>�W�r</B></FONT>
	</TH>
        [IF is_owner]
	  <TH><FONT SIZE="-1"><B>����</B></FONT>
	  </TH>
	  [IF sortby=date]
  	    <TH NOWRAP BGCOLOR="[selected_color]">
	    <FONT COLOR="[bg_color]" SIZE="-1"><b>���</b></FONT>
	  [ELSE]
	    <TH NOWRAP><FONT SIZE="-1">
	    <A HREF="[path_cgi]/review/[list]/1/[size]/date" >
	    <b>���</b></A></FONT>
	  [ENDIF]
          </TH>
        [ENDIF]
      </TR>
      
      [FOREACH u IN members]
        <TR>
	 [IF is_owner]
	    <TD>
	        <INPUT TYPE=checkbox name="email" value="[u->escaped_email]">
	    </TD>
	 [ENDIF]
	 [IF u->bounce]
	  <TD NOWRAP><FONT SIZE=-1>
	 
	      [IF is_owner]
		<A HREF="[path_cgi]/editsubscriber/[list]/[u->escaped_email]/review">[u->email]</A>
	      [ELSE]
 	        [u->email]
 	      [ENDIF]
	  </FONT></TD>
            <TD ALIGN="right"BGCOLOR="[error_color]"><FONT SIZE=-1>
		<FONT COLOR="[bg_color]"><B>�h�H</B></FONT>
	    </TD>

	 [ELSE]
	  <TD COLSPAN=2 NOWRAP><FONT SIZE=-1>
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
	    <TD ALIGN="center"NOWRAP><FONT SIZE=-1>
	      [u->date]
	    </FONT></TD>
       	  [ENDIF]
        </TR>
        [END]


      </TABLE>
    <TABLE WIDTH=100% BORDER=0>
    <TR><TD ALIGN="left">
      [IF is_owner]

        <!--INPUT TYPE="submit" NAME="action_del" VALUE="Delete selected email addresses" onClick="return request_confirm('Do you really want to unsubscribe ALL selected subscribers ?')"-->

	<INPUT TYPE="submit" NAME="action_del" VALUE="�R���襤���l��a�}">

        <INPUT TYPE="checkbox" NAME="quiet"> �w�R
      [ENDIF]
    </TD>

   [IF action<>search]
    <TD ALIGN="right">
       [IF prev_page]
	 <A HREF="[path_cgi]/review/[list]/[prev_page]/[size]/[sortby]"><IMG SRC="[icons_url]/left.png" BORDER=0 ALT="�e�@��"></A>
       [ENDIF]
       [IF page]
  	  [page]/[total_page]
       [ENDIF]
       [IF next_page]
	  <A HREF="[path_cgi]/review/[list]/[next_page]/[size]/[sortby]"><IMG SRC="[icons_url]/right.png" BORDER=0 ALT="��@��"></A>
       [ENDIF]
    </TD>
   [ENDIF]
    </TR>
    </TABLE>
    </FORM>






