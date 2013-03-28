# Setup development paths

# Usually, this can be arranged with PERL5LIB, however we have daemons here.

use lib
  '/home/sympa/lib',
  '/home/sympa/ext/NetVOOT/lib',
  '/home/sympa/ext/OAuth1/lib',
  '/home/sympa/ext/OAuth2/lib',
  '/home/sympa/ext/Plugin/lib',
  '/home/sympa/ext/VOOT/lib'
  ;
