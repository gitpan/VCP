package RevML::Doctype::v0_29 ;

##
## THIS FILE CREATED AUTOMATICALLY: YOU MAY LOSE ANY EDITS IF YOU MOFIFY IT.
##
## When: Wed May  8 16:40:27 2002
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
    'NAME' => 2,
    'PUBID' => 4,
    'ELTS' => 1,
    'SYSID' => 3
  },
  {
    'rev' => bless( [
      {
        'NAMES' => 5,
        'ATTDEFS' => 1,
        'DECLARED' => 3,
        'NAME' => 4,
        'CONTENT' => 2,
        'TODO' => 7,
        'PATHS' => 6
      },
      undef,
      '^<name>(?:<type><rev_id>(?:<change_id>)?<digest>|<type>(?:<cvs_info>|<p4_info>|<source_safe_info>|<pvcs_info>)?(?:<branch_id>)?<rev_id>(?:<change_id>)?<time>(?:<mod_time>)?<user_id>(?:<p4_action>|<sourcesafe_action>)?(?:<label>)*(?:<lock>)?(?:<comment>)?(?:<move>|(?:<content>|(?:<base_name>)?<base_rev_id><delta>)<digest>)|(?:<type>)?(?:<cvs_info>|<p4_info>|<source_safe_info>|<pvcs_info>)?(?:<branch_id>)?(?:<rev_id>)?(?:<change_id>)?(?:<time>)?(?:<mod_time>)?(?:<user_id>)?(?:<p4_action>|<sourcesafe_action>)?(?:<label>)*(?:<lock>)?(?:<comment>)?<delete>)$',
      1,
      'rev',
      [
        'p4_info',
        'cvs_info',
        'sourcesafe_action',
        'rev_id',
        'delta',
        'source_safe_info',
        'name',
        'mod_time',
        'pvcs_info',
        'label',
        'base_name',
        'type',
        'delete',
        'user_id',
        'p4_action',
        'time',
        'comment',
        'content',
        'branch_id',
        'lock',
        'change_id',
        'digest',
        'base_rev_id',
        'move'
      ]
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
    'branch_map_sn' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'branch_map_sn',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'base_name' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'base_name',
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
    'rep_desc' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<char>)*$',
      1,
      'rep_desc',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'p4_action' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'p4_action',
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
    'time' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'time',
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
    'branch_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'branch_id',
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
    'digest' => bless( [
      {},
      {
        'type' => bless( [
          {
            'QUANT' => 4,
            'TYPE' => 5,
            'NAME' => 2,
            'OUT_DEFAULT' => 3,
            'DEFAULT' => 1
          },
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
    'cvs_branch_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'cvs_branch_id',
      []
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
    'sourcesafe_action' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'sourcesafe_action',
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
    'file_count' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'file_count',
      []
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
    'revml' => bless( [
      {},
      {
        'version' => bless( [
          {},
          '0.29',
          'version',
          undef,
          '#FIXED',
          'CDATA'
        ], 'XML::Doctype::AttDef' )
      },
      '^<time><rep_type><rep_desc>(?:<comment>)?(?:<file_count>)?(?:<branch_map_id><branch_map_sn>|(?:<branch>)*)?<rev_root>(?:<rev>)*$',
      1,
      'revml',
      [
        'rev',
        'rep_desc',
        'rep_type',
        'comment',
        'branch_map_sn',
        'rev_root',
        'branch_map_id',
        'branch',
        'file_count',
        'time'
      ]
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
    'mod_time' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'mod_time',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'rep_type' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'rep_type',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'pvcs_info' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?|<trunk_rev_id>|<attrib>|<char>)*$',
      1,
      'pvcs_info',
      [
        'attrib',
        'char',
        'trunk_rev_id'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'branch_map_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'branch_map_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'sourcesafe_branch_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'sourcesafe_branch_id',
      []
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
    'type' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'type',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'trunk_rev_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'trunk_rev_id',
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
    'p4_branch_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'p4_branch_id',
      []
    ], 'XML::Doctype::ElementDecl' ),
    'branch' => bless( [
      {},
      undef,
      '^<branch_id>(?:<cvs_branch_id>)?(?:<p4_branch_id>)?(?:<sourcesafe_branch_id>)?$',
      1,
      'branch',
      [
        'branch_id',
        'sourcesafe_branch_id',
        'p4_branch_id',
        'cvs_branch_id'
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
    'content' => bless( [
      {},
      {
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
      'content',
      [
        'char'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'lock' => bless( [
      {},
      undef,
      '^(?:<time>)?<user_id>$',
      1,
      'lock',
      [
        'user_id',
        'time'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'move' => bless( [
      {},
      undef,
      '^<name>$',
      1,
      'move',
      [
        'name'
      ]
    ], 'XML::Doctype::ElementDecl' ),
    'base_rev_id' => bless( [
      {},
      undef,
      '^(?:(?:#PCDATA)?)$',
      1,
      'base_rev_id',
      []
    ], 'XML::Doctype::ElementDecl' )
  },
  'revml',
  undef,
  undef
], 'RevML::Doctype' );
$doctype->[1]{'cvs_info'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'branch_map_sn'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'base_name'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'user_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'rep_desc'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'p4_action'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'rev_root'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'time'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'comment'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'branch_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'change_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'digest'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'digest'}[1]{'encoding'}[0] = $doctype->[1]{'digest'}[1]{'type'}[0];
$doctype->[1]{'cvs_branch_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'p4_info'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'sourcesafe_action'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'rev_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'char'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'char'}[1]{'code'}[0] = $doctype->[1]{'digest'}[1]{'type'}[0];
$doctype->[1]{'file_count'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'delta'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'delta'}[1]{'type'}[0] = $doctype->[1]{'digest'}[1]{'type'}[0];
$doctype->[1]{'delta'}[1]{'encoding'}[0] = $doctype->[1]{'digest'}[1]{'type'}[0];
$doctype->[1]{'source_safe_info'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'revml'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'revml'}[1]{'version'}[0] = $doctype->[1]{'digest'}[1]{'type'}[0];
$doctype->[1]{'name'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'mod_time'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'rep_type'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'pvcs_info'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'branch_map_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'sourcesafe_branch_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'label'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'type'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'trunk_rev_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'delete'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'p4_branch_id'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'branch'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'attrib'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'content'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'content'}[1]{'encoding'}[0] = $doctype->[1]{'digest'}[1]{'type'}[0];
$doctype->[1]{'lock'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'move'}[0] = $doctype->[1]{'rev'}[0];
$doctype->[1]{'base_rev_id'}[0] = $doctype->[1]{'rev'}[0];

 1 ;
