[FOREACH notice IN notices]

[IF notice_msg=sent_to_owner]
�z���ШD�w�g�Q��o�� Mailing List �Ҧ���

[ELSIF notice_msg=performed]
[notice->action]: �ާ@���\

[ELSIF notice_msg=list_config_updated]
�]�w���w�g�Q��s

[ELSIF notice_msg=upload_success] 
���\�W�Ǥ�� [notice->path] !

[ELSIF notice_msg=save_success] 
��� [notice->path] �w�O�s

[ELSE]
[notice->msg]

[ENDIF]

<BR>
[END]




