package RevML::Doctype::v0_35 ;

##
## THIS FILE CREATED AUTOMATICALLY: YOU MAY LOSE ANY EDITS IF YOU MOFIFY IT.
##
## When: Fri Dec  5 15:04:04 2003
## By:   RevML::Doctype, v0.1, (XML::Doctype, v0.11)
##

require XML::Doctype ;

sub import {
   my $pkg = shift ;
   my $callpkg = caller ;
   $XML::Doctype::_default_dtds{$callpkg} = $doctype ;
}

$doctype = bless( [
  {
    'ELTS' => 1,
    'NAME' => 2,
    'SYSID' => 3,
    'PUBID' => 4
  },
  {
    'move' => bless( [
      {
        'PATHS' => 6,
        'DECLARED' => 3,
        'NAME' => 4,
        'TODO' => 7,
        'NAMES' => 5,
        'CONTENT' => 2,
        'ATTDEFS' => 1
      },
      undef,
      '^<name>$',
      1,
      'move',
      [
        'name'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'lock' => bless( [
      {},
      undef,
      '^(?:<time>)?<user_id>$',
      1,
      'lock',
      [
        'time',
        'user_id'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'source_filebranch_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'source_filebranch_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'content' => bless( [
      {},
      {
        'encoding' => bless( [
          {
            'NAME' => 2,
            'DEFAULT' => 1,
            'TYPE' => 5,
            'QUANT' => 4,
            'OUT_DEFAULT' => 3
          },
          undef,
          'encoding',
          undef,
          '#REQUIRED',
          '(none|base64)'
        ], 'XML::Doctype::AttDef' )
      },
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'content',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'clone' => bless( [
      {},
      undef,
      undef,
      undef,
      'clone',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'rev_root' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'rev_root',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'branch_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'branch_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'sourcesafe_action' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'sourcesafe_action',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'name' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'name',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'rep_type' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'rep_type',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'branch_creation' => bless( [
      {},
      undef,
      undef,
      undef,
      'branch_creation',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'p4_action' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'p4_action',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'source_safe_info' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'source_safe_info',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'delta' => bless( [
      {},
      {
        'type' => bless( [
          {},
          undef,
          'type',
          undef,
          '#REQUIRED',
          '(diff-u)'
        ], 'XML::Doctype::AttDef' ),
        'encoding' => bless( [
          {},
          undef,
          'encoding',
          undef,
          '#REQUIRED',
          '(none|base64)'
        ], 'XML::Doctype::AttDef' )
      },
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'delta',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'attrib' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'attrib',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'delete' => bless( [
      {},
      undef,
      'EMPTY',
      1,
      'delete',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'rev' => bless( [
      {},
      {
        'id' => bless( [
          {},
          undef,
          'id',
          undef,
          '#REQUIRED',
          'CDATA'
        ], 'XML::Doctype::AttDef' )
      },
      '^<name><source_name><source_filebranch_id><source_repo_id>(?:<type>(?:<branch_id><source_branch_id>)?<rev_id><source_rev_id>(?:<change_id><source_change_id>)?<digest>|(?:<type>)?(?:<branch_id><source_branch_id>)?<rev_id><source_rev_id>(?:<change_id><source_change_id>)?(?:<time>)?(?:<mod_time>)?(?:<user_id>)?(?:<label>)*(?:<comment>)?<previous_id>(?:<branch_creation>|<clone>|<placeholder>)|<type>(?:<cvs_info>|<p4_info>|<source_safe_info>|<pvcs_info>)?(?:<branch_id><source_branch_id>)?<rev_id><source_rev_id>(?:<change_id><source_change_id>)?<time>(?:<mod_time>)?<user_id>(?:<p4_action>|<sourcesafe_action>)?(?:<label>)*(?:<lock>)?(?:<comment>)?(?:<move>|(?:<previous_id>)?(?:<content>|<delta>)<digest>)|(?:<type>)?(?:<cvs_info>|<p4_info>|<source_safe_info>|<pvcs_info>)?(?:<branch_id><source_branch_id>)?(?:<rev_id>)?(?:<source_rev_id>)?(?:<change_id><source_change_id>)?(?:<time>)?(?:<mod_time>)?(?:<user_id>)?(?:<p4_action>|<sourcesafe_action>)?(?:<label>)*(?:<lock>)?(?:<comment>)?(?:<previous_id>)?<delete>)$',
      1,
      'rev',
      [
        'move',
        'lock',
        'content',
        'source_filebranch_id',
        'clone',
        'branch_id',
        'sourcesafe_action',
        'name',
        'branch_creation',
        'p4_action',
        'source_safe_info',
        'delta',
        'delete',
        'cvs_info',
        'type',
        'user_id',
        'label',
        'time',
        'mod_time',
        'source_branch_id',
        'source_rev_id',
        'pvcs_info',
        'p4_info',
        'rev_id',
        'placeholder',
        'previous_id',
        'change_id',
        'source_change_id',
        'source_name',
        'source_repo_id',
        'comment',
        'digest'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'label' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'label',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'user_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'user_id',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'type' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'type',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'cvs_info' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'cvs_info',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'trunk_rev_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'trunk_rev_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'time' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'time',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'mod_time' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'mod_time',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'source_branch_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'source_branch_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'source_rev_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'source_rev_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'pvcs_info' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<trunk_rev_id>|<attrib>|<char>)*$',
      1,
      'pvcs_info',
      [
        'char',
        'attrib',
        'trunk_rev_id'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'p4_info' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'p4_info',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'branches' => bless( [
      {},
      undef,
      undef,
      undef,
      'branches',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'placeholder' => bless( [
      {},
      undef,
      undef,
      undef,
      'placeholder',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'rev_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'rev_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'p4_branch_spec' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'p4_branch_spec',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'previous_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'previous_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'change_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'change_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'source_change_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'source_change_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'source_name' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'source_name',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'revml' => bless( [
      {},
      {
        'version' => bless( [
          {},
          '0.35',
          'version',
          undef,
          '#FIXED',
          'CDATA'
        ], 'XML::Doctype::AttDef' )
      },
      '^<time><rep_type><rep_desc>(?:<comment>)?<rev_root>(?:<branches>)?(?:<rev>)*$',
      1,
      'revml',
      [
        'comment',
        'rev_root',
        'time',
        'rev',
        'branches',
        'rep_desc',
        'rep_type'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'source_repo_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'source_repo_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'comment' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'comment',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'char' => bless( [
      {},
      {
        'code' => bless( [
          {},
          undef,
          'code',
          undef,
          '#REQUIRED',
          'CDATA'
        ], 'XML::Doctype::AttDef' )
      },
      'EMPTY',
      1,
      'char',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'digest' => bless( [
      {},
      {
        'type' => bless( [
          {},
          undef,
          'type',
          undef,
          '#REQUIRED',
          '(MD5)'
        ], 'XML::Doctype::AttDef' ),
        'encoding' => bless( [
          {},
          undef,
          'encoding',
          undef,
          '#REQUIRED',
          '(base64)'
        ], 'XML::Doctype::AttDef' )
      },
      '^(?:(?:#PCDATA)?)$',
      1,
      'digest',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'rep_desc' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'rep_desc',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' )
  },
  'revml',
  undef,
  undef
], 'RevML::Doctype' );
$doctype->[1]{'lock'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'source_filebranch_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'content'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'clone'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'rev_root'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'branch_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'sourcesafe_action'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'name'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'rep_type'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'branch_creation'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'p4_action'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'source_safe_info'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'delta'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'delta'}[1]{'type'}[0] = $doctype->[1]{'content'}[1]{'encoding'}[0];
$doctype->[1]{'delta'}[1]{'encoding'}[0] = $doctype->[1]{'content'}[1]{'encoding'}[0];
$doctype->[1]{'attrib'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'delete'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'rev'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'rev'}[1]{'id'}[0] = $doctype->[1]{'content'}[1]{'encoding'}[0];
$doctype->[1]{'label'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'user_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'type'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'cvs_info'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'trunk_rev_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'time'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'mod_time'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'source_branch_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'source_rev_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'pvcs_info'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'p4_info'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'branches'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'placeholder'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'rev_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'p4_branch_spec'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'previous_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'change_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'source_change_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'source_name'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'revml'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'revml'}[1]{'version'}[0] = $doctype->[1]{'content'}[1]{'encoding'}[0];
$doctype->[1]{'source_repo_id'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'comment'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'char'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'char'}[1]{'code'}[0] = $doctype->[1]{'content'}[1]{'encoding'}[0];
$doctype->[1]{'digest'}[0] = $doctype->[1]{'move'}[0];
$doctype->[1]{'digest'}[1]{'type'}[0] = $doctype->[1]{'content'}[1]{'encoding'}[0];
$doctype->[1]{'digest'}[1]{'encoding'}[0] = $doctype->[1]{'content'}[1]{'encoding'}[0];
$doctype->[1]{'rep_desc'}[0] = $doctype->[1]{'move'}[0];

 1 ;
