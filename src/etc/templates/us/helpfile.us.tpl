[IF  user->lang=fr]

              SYMPA -- Systeme de Multi-Postage Automatique
 
                       Guide de l'utilisateur


SYMPA est un gestionnaire de listes electroniques. Il permet d'automatiser
les fonctions de gestion des listes telles les abonnements, la moderation
et la gestion des archives.

Toutes les commandes doivent etre adressees a l'adresse electronique
[conf->sympa]

Il est possible de mettre plusieurs commandes dans chaque message : les
commandes doivent apparaitre dans le corps du message et chaque ligne ne
doit contenir qu'une seule commande. Sympa ignore le corps du message
si celui-ci n'est de type "Content-type: text/plain", mais m�me si vous
etes fanatique d'un agent de messagerie qui fabrique systematiquement des
messages "multipart" ou "text/html", les commandes placees dans le sujet
du messages sont reconnues.

Les commandes disponibles sont :

 HELp                        * Ce fichier d'aide
 LISts                       * Annuaire des listes geres sur ce noeud
 REView <list>               * Connaitre la liste des abonnes de <list>
 WHICH                       * Savoir � quelles listes on est abonn�
 SUBscribe <list> Prenom Nom * S'abonner ou confirmer son abonnement a la 
			       liste <list>
 SIGnoff <list|*> [user->email]    * Quitter la liste <list>, ou toutes les listes.
                               O� [user->email] est facultatif

 SET <list|*> NOMAIL         * Suspendre la reception des messages de <list>
 SET <list|*> DIGEST         * Reception des message en mode compilation
 SET <list|*> SUMMARY        * Reception de la liste des messages uniquement
 SET <list|*> MAIL           * Reception de la liste <list> en mode normal
 SET <list|*> CONCEAL        * Passage en liste rouge (adresse d'abonn� cach�e)
 SET <list|*> NOCONCEAL      * Adresse d'abonn� visible via REView

 INFO <list>                 * Informations sur une liste
 INDex <list>                * Liste des fichiers de l'archive de <list>
 GET <list> <fichier>        * Obtenir <fichier> de l'archive de <list>
 LAST <list>		     * Obtenir le dernier message de <list>
 INVITE <list> <email>       * Inviter <email> a s'abonner � <list>
 CONFIRM <clef>	 	     * Confirmation pour l'envoi d'un message
			       (selon config de la liste)
 QUIT                        * Indique la fin des commandes (pour ignorer 
                               une signature

[IF is_owner]
Commandes r�serv�es aux propri�taires de listes:
 
 ADD <list> user@host Prenom Nom * Ajouter un utilisateur a une liste
 DEL <list> user@host            * Supprimer un utilisateur d'une liste
 STATS <list>                    * Consulter les statistiques de <list>
 EXPire <list> <ancien> <delai>  * D�clanche un processus d'expiration pour
                                   les abonn�s � la liste <list> n'ayant pas
				   confirm� leur abonnement depuis <ancien>
				   jours. Les abonn�s ont <delai> jours pour
				   confirmer
 EXPireINDex <list>              * Connaitre l'�tat du processus d'expiration
                                   en cours pour la liste <list>
 EXPireDEL <list>                * D�sactive le processus d'espiration de la
                                   liste <list>

 REMind <list>                   * Envoi � chaque abonn� un message
                                   personnalis� lui rappelant
                                   l'adresse avec laquelle il est abonn�.
[ENDIF]

[IF is_editor]

Commandes r�serv�es aux mod�rateurs de listes :

 DISTribute <list> <clef>        * Mod�ration : valider un message
 REJect <list> <clef>            * Mod�ration : invalider un message
 MODINDEX <list>                 * Mod�ration : consulter la liste des messages
                                   � mod�rer
[ENDIF]

[ELSIF user->lang=it]

		  SYMPA -- Mailing List Manager

	     		Guida utente

SYMPA e' un gestore di liste di posta elettronica.
Permette di automatizzare le funzioni di gestione delle liste:
iscrizioni, cancellazioni, moderazione, archiviazione.

Tutti i comandi devono essere inviati all'indirizzo
  [conf->sympa]

E'  possibile  inserire piu' di un comando in ciascun messaggio:
i comandi devono essere scritti nel corpo del messaggio, uno per riga.

Il formato deve essere text/plain: se proprio siete fanatici dei
messaggi "multipart" o "text/html", potete inserire un comando
nell'oggetto del messaggio.

Elenco dei comandi:

  HELp                  * Questo file di istruzioni

  LISts                 * Lista delle liste gestite da questo server

  REView <list>         * Elenco degli iscritti

  WHICH                 * Mostra in quali liste sei iscritto

  SUBscribe <list> [Nome Cognome]
                        * Iscrizione

  SIGnoff <list|*> [user->email]
                        * Cancellazione dalla lista o da tutte le liste

  SET <list|*> NOMAIL   * Sospende la ricezione dei messaggi

  SET <list|*> DIGEST   * Ricezione dei messaggi in modo aggregato

  SET <list|*> SUMMARY  * Receiving the message index only

  SET <list|*> MAIL     * Ricezione dei messaggi in modo normale

  SET <list> CONCEAL    * Nasconde il proprio indirizzo dall'elenco
                          ottenuto col comando REV

  SET <list> NOCONCEAL  * Rende visibile il proprio indirizzo
                          nell'elenco ottenuto col comando REV

  INFO <list>           * Informazioni sulla lista

  INDex <list>          * Indice dei file di archivio

  GET <list> <file>     * Scarica il <file> dall'archivio

  LAST <list>           * Prende l'ultimo messaggio

  INVITE <list> <email> * Invita l'utente <email> a iscriversi

  CONFIRM <key>         * Conferma per l'invio di un messaggio (dipende
                          dalla configurazione della lista)

  QUIT                  * Fine dei comandi (per ignorare la firma)

[IF is_owner]
Comandi riservati ai gestori delle liste:

 ADD <list> user@host [Nome Cognome]
                        * Aggiunge l'utente

 DEL <list> user@host   * Cancella l'utente

 STATS <list>           * Consulta le statistiche

 EXPire <list> <old> <delay>
                        * Inizia un processo di scadenza per gli utenti
                          che non hanno confermato l'iscrizione da <old>
                          giorni.
                          Restano <delay> giorni per confermare.

 EXPireINDex <list>     * Mostra lo stato del processo di scadenza
                          corrente per la lista <list>

 EXPireDEL <list>       * Annulla il processo di scadenza per la lista

 REMIND <list>          * Invia a ciascun utente un messaggio
                          personalizzato per ricordare con quale
                          indirizzo e' iscritto
[ENDIF]

[IF is_editor]


Comandi riservati ai moderatori delle liste:

 DISTribute <list> <key>
                        * Moderazione: convalida di messaggio

 REJect <list> <key>    * Moderazione: rifiuto di messaggio

 MODINDEX <list>        * Moderazione: consultazione dell'elenco dei
                          messaggi da moderare
[ENDIF]

[ELSIF user->lang=de]

              SYMPA -- Systeme de Multi-Postage Automatique
                         (Automatisches Mailing System)

                             Benutzungshinweise


--------------------------------------------------------------------------------
SYMPA ist ein elektronischer Mailing-Listen-Manager, der Funktionen zur Listen-
verwaltung automatisiert, wie zum Beispiel Abonnieren, Moderieren und Verwalten 
von Mail-Archiven.

Alle Kommandos muessen an die Mail-Adresse [conf->sympa] geschickt werden.

Sie koennen mehrere Kommandos in einer Nachricht abschicken. Diese Kommandos
muessen im Hauptteil der Nachricht stehen und jede Zeile darf nur ein Kommando 
enthalten. Der Mail-Hauptteil wird ignoriert, wenn der Content-Type nicht 
text/plain ist. Sollten Sie ein Mail-Programm verwenden, das jede Nachricht 
als Multipart oder text/html sendet, so kann das Kommando alternativ in der 
Betreffzeile untergebracht werden.

Verfuegbare Kommandos:

 HELp                        * Diese Hilfedatei
 INFO                        * Information ueber die Liste
 LISts                       * Auflistung der verwalteten Listen
 REView <list>               * Anzeige der Abonnenten der Liste <list>
 WHICH                       * Anzeige der Listen, die Sie abonniert haben
 SUBscribe <list> <GECOS>    * Abonnieren bzw. Bestaetigen eines Abonnements
                               der Liste <list>, <GECOS> ist eine zusaetzliche
                               Information ueber den Abonnenten
 UNSubscribe <list> <EMAIL>  * Abbestellen der Liste <list>. <EMAIL> kann
                               optional angegeben werden. Nuetzlich, wenn
                               verschieden von Ihrer "Von:"-Adresse.
 UNSubscribe * <EMAIL>       * Abbestellen aller Listen

 SET <list|*> NOMAIL         * Abonnement der Liste <list> aussetzen
 SET <list|*> DIGEST         * Mail-Empfang im Kompilierungs-Modus
 SET <list|*> SUMMARY        * Receiving the message index only
 SET <list|*> MAIL           * Listenempfang von <list> im Normal-Modus
 SET <list|*> CONCEAL        * Bei Auflistung (REVIEW) Mail-Adresse nicht
                               anzeigen (versteckte Abonnement-Adresse)
 SET <list> NOCONCEAL        * Bei Auflistung (REVIEW) Mail-Adresse wieder
                               sichtbar machen

 INDex <list>                * Auflistung der Dateien im Mail-Archive <list>
 GET <list> <file>           * Datei <file> des Mail-Archivs <list> anfordern
 LAST <list>                 * Used to received the last message from <list>
 INVITE <list> <email>       * Invite user <email> for subscribtion in <list>
 CONFIRM <key>               * Bestaetigung fuer Gueltigkeit der Mail-Adresse
                               (haengt von Konfiguration der Liste ab)
 QUIT                        * Zeigt Ende der Kommandoliste an (wird verwendet
                               zum Ueberlesen der Signatur einer Mail)


[IF is_owner]
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
Die folgenden Kommandos sind nur fuer Eigentuemer bzw. Moderatoren der Listen
zulaessig:

 ADD <list> user@host First Last * Benutzer der Liste <list> hinzufuegen
 DEL <list> user@host            * Benutzer von der Liste <list> entfernen
 STATS <list>                    * Statistik fuer <list> abrufen
 EXPire <list> <old> <delay>     * Ablauffrist fuer Liste <list> setzen fuer
                                   Abonnenten (Subscribers), die nicht inner-
                                   halb von <old> Tagen eine Bestaetigung
                                   schicken. Diese Ablauffrist beginnt erst
                                   nach <delay> Tagen (nach SUBSCRIBE).
 EXPireINDex <list>              * Anzeige des aktuellen Status fuer Ablauf-
                                   fristen der Liste <list>
 EXPireDEL <list>                * Ablauffrist fuer Liste <list> loeschen.

 REMIND <list>                   * Erinnerungsnachricht an jeden Abonnenten
                                   schicken (damit kann jedem Benutzer
                                   mitgeteilt werden, unter welcher
                                   Adresse er die Liste abonniert hat)
[ENDIF]
[IF is_editor]
 DIStribute <list> <clef>        * Moderation: Nachricht ueberpruefen
 REJect <list> <clef>            * Moderation: Nachricht ablehnen
 MODINDEX <list>                 * Moderation: Liste der Nachrichten der zu
                                   moderierenden Nachrichten
[ENDIF]

[ELSIF user->lang=es]
              SYMPA -- Systeme de Multi-Postage Automatique
                       (Sistema Automatico de Listas de Correo)

                                Gu�a de Usuario


SYMPA es un gestor de listas de correo electr�nicas que automatiza las funciones
habituales de una lista como la subscripci�n, moderaci�n y archivo de mensajes.

Todos los comandos deben ser enviados a la direcci�n [conf->sympa]

Se pueden poner m�ltiples comandos en un mismo mensaje. Estos comandos tienen que
aparecer en el texto del mensaje y cada l�nea debe contener un �nico comando.
Los mensajes se deben enviar como texto normal (text/plain) y no en formato HTML.
En cualquier caso, los mensajes en el sujeto del mensaje tambi�n son interpretados.


Los comandos disponibles son:

 HELp                        * Este fichero de ayuda
 INFO                        * Informaci�n de una lista
 LISts                       * Directorio de todas las listas de este sistema
 REView <lista>              * Muestra los subscriptores de <lista>
 WHICH                       * Muestra a qu� listas est� subscrito
 SUBscribe <lista> <GECOS>   * Para subscribirse o confirmar una subscripci�n
                               a <lista>.  <GECOS> es informaci�n adicional
                               del subscriptor (opcional).

 UNSubscribe <lista> <EMAIL> * Para anular la subscripci�n a <lista>.
                               <EMAIL> es opcional y es la direcci�n elec-
                               tr�nica del subscriptor, �til si difiere
                               de la de direcci�n normal "De:".

 UNSubscribe * <EMAIL>       * Para borrarse de todas las listas

 SET <lista> NOMAIL          * Para suspender la recepci�n de mensajes de <lista>
 SET <lista|*> DIGEST        * Para recibir los mensajes recopilados
 SET <lista|*> SUMMARY       * Receiving the message index only
 SET <lista|*> MAIL          * Para activar la recepci�n de mensaje de <lista>
 SET <lista|*> CONCEAL       * Ocultar la direcci�n para el comando REView
 SET <lista|*> NOCONCEAL     * La direcci�n del subscriptor es visible via REView

 INDex <lista>               * Lista el archivo de <lista>
 GET <lista> <fichero>       * Para obtener el <fichero> de <lista>
 LAST <lista>                * Usado para recibir el �ltimo mensaje enviado a <lista>
 INVITE <lista> <email>      * Invitaci�n a <email> a subscribirse a <lista>
 CONFIRM <key>               * Confirmaci�n para enviar un mensaje
                               (depende de la configuraci�n de la lista)
 QUIT                        * Indica el fin de los comandos


[IF is_owner]
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=-=-=-
Los siguientes comandos son unicamente para los propietarios o moderadores de las listas:

ADD <lista> <email> Nombre Apellido   * Para a�adir un nuevo usuario a <lista>
DEL <lista> <email>                   * Para elimiar un usuario de <lista>
STATS <lista>                         * Para consultar las estad�sticas de <lista>

EXPire <lista> <dias> <espera>        * Para comenzar un proceso de expiraci�n para
                                        aquellos subscriptores que no han confirmado 
                                        su subscripci�n desde hace tantos <dias>.
                                        Los subscriptores tiene tantos d�as de <espera> 
                                        para confirmar.

EXPireINDEx <lista>                   * Muestra el actual proceso de expiraci�n de <lista>
EXPireDEL <lista>                     * Desactiva el proceso de expiraci�n de <lista>

REMIND <lista>                        * Envia un mensaje a cada subscriptor (esto es una
                                        forma de recordar a cualquiera con qu� e-mail
                                        est� subscrito).

[ENDIF]
[IF is_editor]

 DISTribute <lista> <clave>           * Moderaci�n: para validar un mensaje
 REJect <lista> <clave>               * Moderaci�n: para denegar un mensaje
 MODINDEX <listaa>                    * Moderaci�n: consultar la lista de mensajes a moderar

[ENDIF]

[ELSE]

              SYMPA -- Systeme de Multi-Postage Automatique
                       (Automatic Mailing System)

                                User's Guide


SYMPA is an electronic mailing-list manager that automates list management
functions such as subscriptions, moderation, and archive management.

All commands must be sent to the electronic address [conf_sympa]

You can put multiple commands in a message. These commands must appear in the
message body and each line must contain only one command. The message body
is ignored if the Content-Type is different from text/plain but even with
crasy mailer using multipart and text/html for any message, commands in the
subject are recognized.

Available commands are:

 HELp                        * This help file
 INFO                        * Information about a list
 LISts                       * Directory of lists managed on this node
 REView <list>               * Displays the subscribers to <list>
 WHICH                       * Displays which lists you are subscribed to
 SUBscribe <list> <GECOS>    * To subscribe or to confirm a subscription to
                               <list>, <GECOS> is an optional information
                               about subscriber.

 UNSubscribe <list> <EMAIL>  * To quit <list>. <EMAIL> is an optional 
                               email address, usefull if different from
                               your "From:" address.
 UNSubscribe * <EMAIL>       * To quit all lists.

 SET <list|*> NOMAIL         * To suspend the message reception for <list>
 SET <list|*> DIGEST         * Message reception in compilation mode
 SET <list|*> SUMMARY        * Receiving the message index only
 SET <list|*> MAIL           * <list> reception in normal mode
 SET <list|*> NOTICE         * Receiving message subject only

 SET <list|*> CONCEAL        * To become unlisted (hidden subscriber address)
 SET <list|*> NOCONCEAL      * Subscriber address visible via REView


 INDex <list>                * <list> archive file list
 GET <list> <file>           * To get <file> of <list> archive
 LAST <list>                 * Used to received the last message from <list>
 INVITE <list> <email>       * Invite <email> for subscribtion in <list>
 CONFIRM <key>               * Confirmation for sending a message (depending
                               on the list's configuration)
 QUIT                        * Indicates the end of the commands (to ignore a
                               signature)

[IF is_owner]
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
The following commands are available only for lists's owners or moderators:

 ADD <list> user@host First Last * To add a user to a list
 DEL <list> user@host            * To delete a user from a list
 STATS <list>                    * To consult the statistics for <list>
 EXPire <list> <old> <delay>     * To begin an expiration process for <list>
                                   subscribers who have not confirmed their
                                   subscription for <old> days. The
                                   subscribers have <delay> days to confirm
 EXPireINDex <list>              * Displays the current expiration process
                                   state for <list>
 EXPireDEL <list>                * To de-activate the expiration process for
                                   <list>

 REMIND <list>                   * Send a reminder message to each
                                   subscriber (this is a way to inform
                                   anyone what is his real subscribing
                                   email).
[ENDIF]
[IF is_editor]

 DISTribute <list> <clef>        * Moderation: to validate a message
 REJect <list> <clef>            * Moderation: to reject a message
 MODINDEX <list>                 * Moderation: to consult the message list to
                                   moderate
[ENDIF]
[ENDIF]

Powered by Sympa [conf->version] : http://listes.cru.fr/sympa/

