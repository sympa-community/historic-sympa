<!-- RCS Identication ; $Revision$ ; $Date$ -->
[FOREACH p IN param]
<A NAME="[p->NAME]">
<B>[p->title]</B> ([p->NAME]):
<DL>
<DD>
[IF p->NAME=add]
  �N�q�\�̷s�WADD �R�O)�� Mailing List ��Privilege
[ELSIF p->NAME=anonymous_sender]
  �b���o�l��e���õo�H�H�l��a�}�C
  �ϥδ��Ѫ��l��a�}�Ӵ�����Ӫ��a�}�C
[ELSIF p->NAME=archive]
  Ū���l��s�ɩM�s�ɶ��j��Privilege
[ELSIF p->NAME=owner]
  �Ҧ��̺޲z Mailing List ���q�\�̡C�L�̥i�H�d�ݭq�\�̡A�q Mailing List ���s�W�R���l��a�}�C
�p�G�z�O Mailing List ��Privilege�Ҧ��̡A�z�i�H��� Mailing List ���䥦�Ҧ��̡C
   Mailing List ��Privilege�Ҧ��̥i�H�ק��䥦�Ҧ��̭n�h���ﶵ�C�C�� Mailing List �u�঳�@��Privilege
�Ҧ��̡F�L(�Φo)���l��a�}����q�����W�i��ק�C
[ELSIF p->NAME=editor]
  �s��t�d�i��������ʺޡC�p�G Mailing List �n�i��ʺޡA�o�� Mailing List ���l��N�����Q��
���s��A�ѥL�̨M�w�O���o�٬O�ڵ����C<BR>
FYI: �w�q�s��̤��|�� Mailing List �Q�ʺޡF�z�����]�m���o�e���ѼơC<BR>
FYI: �p�G Mailing List �Q�ʺޡA�Ĥ@�ӨM�w���o�Ωڵ��l�󪺽s��N����L���s��i��M�w�C
�p�G�S������s��U�M�w�A�l��N�O�d�b�ʺ޶��C���C
[ELSE]
  �L�i�^�i
[ENDIF]

</DL>
[END]
	
