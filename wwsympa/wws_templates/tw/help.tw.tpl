<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF help_topic]
 [PARSE help_template]

[ELSE]
<BR>
�z�i�H�b�o�̳X�ݶl�� Mailing List  Server  <B>[conf->email]@[conf->host]</B>�C
<BR><BR>
�M Sympa �����H�R�O(�q�L�l��i��)�ۦP���\��i�H�q���ŧO���Τ�ɭ��W�ϥΡC
WWSympa ���ѥi�ۭq�����ҡA�i�ϥΥH�U�\��: 

<UL>
<LI><A HREF="[path_cgi]/pref">�ﶵ</A>: �Τ�ﶵ�C�ȴ��ѵ��T�{�������Τ�C

<LI><A HREF="[path_cgi]/lists">���} Mailing List </A>:  Server �W���Ѫ����} Mailing List �C

<LI><A HREF="[path_cgi]/which">�z�q�\�� Mailing List </A>: �z�@���q�\�̩ξ֦��̪����ҡC

<LI><A HREF="[path_cgi]/loginrequest"> Login </A>��<A HREF="[path_cgi]/logout">Logout</A>: �q WWSympa �W Login �ΰh�X�C
</UL>

<H2> Login </H2>

[IF auth=classic]
�b�������(<A HREF="[path_cgi]/loginrequest"> Login </A>)�ɡA�д��ѱz�� Email �a�}�M�������K�X�C
<BR><BR>
�@���q�L����A�@�ӥ]�t�z Login �T���� <I>cookie</I> �ϱz�������X�� WWSympa�C
�o�� <I>cookie</I> ���ͦs���i�H�b�z��<A HREF="[path_cgi]/pref">�ﶵ</A>�����w�C

<BR><BR>
[ENDIF]

�z�i�H�b����ɭԨϥ�<A HREF="[path_cgi]/logout">Logout�</>�\�� Logout <I>cookie</I>)�C

<H5> Login ���D</H5>

<I>�ڤ��O Mailing List ���q�\��</I><BR>
�ҥH�z�S���b Sympa ���Τ� Database ���n�O�B�L�k Login �C
�p�G�z�q�\�F�@�� Mailing List �AWWSympa �N���z�@�Ӫ�l�K�X�C
<BR><BR>

<I>�ڬO�ܤ֤@�� Mailing List ���q�\�̡A���O�ڨS���K�X</I><BR>
�n����K�X:
<A HREF="[path_cgi]/remindpasswd">[path_cgi]/remindpasswd</A>
<BR><BR>

<I>�ڧѰO�F�K�X</I><BR>
WWSympa �i�H�q�L�q�l�l��ӧi�D�z�K�X:
<A HREF="[path_cgi]/remindpasswd">[path_cgi]/remindpasswd</A>

<P>

�p�G�n�p�� Server �޲z��: <A HREF="mailto:listmaster@[conf->host]">listmaster@[conf->host]</A>
[ENDIF]













