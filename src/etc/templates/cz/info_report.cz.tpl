Informace o konferenci [list->name]@[list->host] :

Subjekt               : [subject]
[FOREACH o IN owner]
Vlastn�k              : [o->gecos] <[o->email]>
[END]
[FOREACH e IN editor]
Moder�tor             : [e->gecos] <[e->email]>
[END]
P�ihl�en�            : [subscribe]
Odhl�en�             : [unsubscribe]
Zas�l�n� zpr�v        : [send]
Seznam �len�          : [review]
Odpov�� na            : [reply_to]
Maxim�ln� velikost    : [max_size]
[IF digest]
Shrnut�               : [digest]
[ENDIF]
Re�im p�ij�m�n� zpr�v : [available_reception_mode]
Domovsk� str�nka      : [url]

[PARSE 'info']
