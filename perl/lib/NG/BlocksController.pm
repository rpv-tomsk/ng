package NG::BlocksController;
use strict;

use Data::Dumper;

our $CACHE;

our $MAX_CACHE_TIME = 300;            #  5 min
our $MAX_CACHE_TIME_VERSIONS = 900;   # 15 min

BEGIN {
    $CACHE = $NG::Application::Cache;
};

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);
    #$self->config();
    return $self; 
};

sub init {
    my $self = shift;
    $self->{_tmplFile} = undef;
    $self->{_ablock} = undef;
    $self->{_blocks} = [];
    $self->{_hblocks} = {};
    $self->{_pObj} = shift;
    #
    $self->{_usedBCodes} = {}; # �������������� � ������� ���� ������
    #
    $self->{_regions} = {};
    $self->{_tmplAttached} = 0; #���� ��� ��������� �������������� �������������� �����
    
    $self;
};

sub loadTemplateBlocks {
    my $self = shift;
    my $tmplFile = shift or die __PACKAGE__."::loadTemplateBlocks(\$): tmplFile expected";
    
    my $cms = $self->cms();

    $self->{_tmplFile} = $tmplFile;
    my $tBlocks = $cms->getTemplateBlocks($tmplFile);
    
    return $cms->error("cms->getTemplateBlocks() returns undef") unless defined $tBlocks;
    return $cms->defError("cms->getTemplateBlocks(): ") if $tBlocks eq 0;
    return $cms->error("cms->getTemplateBlocks() result is not ARRAYREF ") unless ref $tBlocks eq "ARRAY";
    
    foreach my $block (@$tBlocks) {
        my $b = $self->_pushBlock($block) or return $cms->error();
        $b->{SOURCE}="tmpl";
    };
    return 1;
};

sub currentLayout {
    my $self = shift;
    return $self->{_tmplFile};
};

sub loadNeighbourBlocks {
    my $self = shift;
    my $pBlock = shift or die __PACKAGE__."::loadNeighbourBlocks(\$): tmplFile expected";
    
    my $cms = $self->cms();

    my $tBlocks = $cms->getNeighbourBlocks($pBlock); # [] of {}.
    
    return $cms->error("cms->getNeighbourBlocks() returns undef") unless defined $tBlocks;
    return $cms->defError("cms->getNeighbourBlocks(): ") if $tBlocks eq 0;
    return $cms->error("cms->getNeighbourBlocks() result is not ARRAYREF ") unless ref $tBlocks eq "ARRAY";
    
    foreach my $block (@$tBlocks) {
        my $b = $self->_pushBlock($block) or return $cms->error();
        $b->{SOURCE}="neigh";
    };
    return 1;
};

sub _pushBlock {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();
    
    return $cms->error("pushBlock(): ����������� ��� ����� CODE") unless $block->{CODE};
    return $cms->error("Block ".$block->{CODE}." already exists, source: ".$self->{_hblocks}->{$block->{CODE}}->{SOURCE}) if exists $self->{_hblocks}->{$block->{CODE}};
    
=comment ����� ���� $block
    ����� ����
     CODE - ������������ ��������. ���� ���������������� ���������� ����� CODE.
     TYPE - ���������� - ������/���� ������. �� ��������� - ������� ��� ��� ���� ������, �������� 0 ��� ���������� �����.

     SOURCE      - ���� �� ��������: push/tmpl/neigh
     KEYS        - �����, ���������� �� ������ getBlockKeys()
       �������������� �����:
            REQUEST          - �����, ���������������� ������� �����.
            VERSION_KEYS     - �� ����� ������ ������� ������� �����.
            NOCACHE          - ���� ������� ���������� �������� ����� � ���.
            MAXAGE           - ������������ ���� ����� �������� � ����.
            ETAG             -
            LM               -
            ALLOWREDIRECT    - ��������� ��-�� ����� �������� ���������� ��������
            USED_VERSIONS    - ������ �� ���� ��������� ��� ������������ �������������� ������.
                                ������ ������� (������ 0) - ������ �������� ������, �������������� ��� ���������� �����
                                ������ ������� (������ 1) - ������ "������ ������", �� ������� �� ���� ����� �������� ������� �������� ������.
                                �������� ������������ ��� ������������ �������� �����, ������������ ��� ���������� � ��� (����������� ��������).
          
          ��� ��:
            RELATED          - ������ ��� ����������� ������, ������������ ��� ������������ ��������.
            HASRELATED       - ������������ � getBlockKeys(), �������, ��� � getBlockContent() ��� �� ���� � RELATED ����� ���������� ������.
            REDIRECT         - �� ������� ��� ��� ������� �� ����, � ����� ��������.
    
     CACHEKEYS   - ����������, ���������� �� ����, ��� �� �������.
        ������ ����������:
            HEADERS          - ���������, ������������ �������� ���������� ��������
            HEADKEYS         - �����, ������������ �������� ���������� ��������
            RELATED          - �����, ������������ � ������� ���������� ��������
            VERSIONS         - ��� ��������, ��������������� ��������� �� VERSION_KEYS
            
            USED_VERSIONS    - ��������, ������������ � ������� ���������� ��������
            ETAG             - ����� �������� ����������� ��������������� ��������
            LM               - 
        
     CONTENT
     VERSIONS    - ������ ��������, ��������������� ��������� �� VERSION_KEYS
     USED_VERSIONS    - ������ ��������, ��������������� ��������� �� CACHEKEYS.USED_VERSIONS
     
     MODULEOBJ   - ������ ������ �����
     
    #���� ������
      CODE = {MODULECODE}_{ACTION}. ACTION - ��� �����, ������� �� ����������� ��������� � ������
      TYPE = 0 ��� �����������
      
      MODULECODE - ��� ����������� ������ ������������ �� CODE
      ACTION     - ��� ����� ������������ �� CODE
    
    #������
      CODE - �������� �������� ������������� ����
      TYPE = 1
      
      MODULECODE - ��� ����������� ������, ��������� �������� - ��������
      ACTION - ������������ ��������, ��������� �������� �� CODE - ����������.
      
      
    #������� ���������, ������� ����������� ����������� � ����������� �����.
      MODULE - ����� ������. ��� ����������, ������������ �� ���� ������ �������
      MODULEROW - ��������� �������� ������. 
=cut

    
    $block->{TYPE} = 0 unless exists $block->{TYPE};
    
    if ($block->{TYPE}) {
        $block->{MODULECODE} ||= $block->{MODULEROW}->{code} if ($block->{MODULEROW} && $block->{MODULEROW}->{code});
        return $cms->error("�� ������� �������� ����� ACTION ��� ������ ������� ".$block->{CODE}) unless $block->{ACTION};
        return $cms->error("�� ������� �������� ����� MODULECODE ��� ������ ������� ".$block->{CODE}) unless $block->{MODULECODE};
    }
    else {
        #���� ������
        if ($block->{CODE} =~ /([^_]+)_(.*)$/) {
            warn "ACTION (".$block->{ACTION}.") != action from CODE (".$block->{CODE}.")" if $block->{ACTION} && $block->{ACTION} ne $2;
            warn "MODULECODE != module code from CODE" if $block->{MODULECODE} && $block->{MODULECODE} ne $1;
            $block->{MODULECODE} = $1;
            $block->{ACTION} = $2;
        }
        elsif ($block->{ACTION} && $block->{MODULECODE}) {
            warn "CODE looks like plugin definition, and ACTION and MODULECODE exists";
            $block->{TYPE} = 1;
        }
        else {
            return $cms->error("�������� CODE (".$block->{CODE}.") �� ������������� ����� MODULECODE_ACTION");
        };
    };
    
    if ($block->{MODULEROW}) {
        return $cms->error("MODULEROW is not HASHREF") unless ref $block->{MODULEROW} eq "HASH";
        return $cms->error("MODULEROW.code != MODULE") if ($block->{MODULEROW} && $block->{MODULEROW}->{code} && $block->{MODULEROW}->{code} ne $block->{MODULECODE});
    };
    
    push @{$self->{_blocks}}, $block;
    $self->{_hblocks}->{$block->{CODE}} = $block;
    return $block;
};

sub pushABlock {
    my $self = shift;
    my $block = $self->_pushBlock(@_) or return $self->cms->error();
    $block->{SOURCE} = "push";
    $self->{_ablock} = $block;
    
    delete $block->{BLOCK};
=head
    ����������������� ����. ������: ������ � ������������.
=cut
    my $neigh = delete $block->{NEIGHBOURS};
    if ($neigh) {
        return $self->cms->error("getActiveBlock() ������ ".(ref $self->{_pObj})." ������ ������������ ��������. NEIGHBOURS �� �������� ��������)") unless ref $neigh eq "ARRAY";
        my $mName = undef;
        foreach my $nb (@$neigh) {
            return $self->cms->error("getActiveBlock() ������ ".(ref $self->{_pObj})." ������ ������������ ��������. � �������� ������� NEIGHBOURS ����������� �������� BLOCK)") unless $nb->{BLOCK};
            unless ($nb->{CODE}) {
                $mName ||= $self->{_pObj}->getModuleCode() or return $self->cms->error();
                $nb->{CODE} = $mName."_".$nb->{BLOCK};
            };
            my $b = $self->_pushBlock($nb) or return $self->cms->error();
            $b->{SOURCE}="neigh";
        };
    };
    
#NG::Profiler::saveTimestamp("pushABlock begin: ".ref($block->{MODULEOBJ})."_".$block->{ACTION},"pushABlock");
    
    #�������� ����� �� ��� ���������� ��������
    my $abKeys = $self->_getBlockKeys($block) or return $self->cms->error();
    #����������� �������� ��� �������� �������� ��������������� �� ��
    return $self->cms->redirect($abKeys->{REDIRECT}) if $abKeys->{REDIRECT};
    #��������� ����������� �����������.
    if (!$abKeys->{REQUEST}) {
        #���� ��� REQUEST ������ ����������� ����������.
        #������� ����� getBlockContent() �� ���������� ������ ������, �� ������ ��������� � � �  - �����������.
        return $self->getBlockContent($block);
    };
    #����������� ��������, ����������� ����� �����������.
    #������� ������� ��� ��������� ��������� ��������.
    #������� � ��� ����� ����� ��������� � ����� ������, ������ �� ����� ���������� (�� ��) �������
    return NG::BlockContent->output("DUMMY") unless $abKeys->{HASRELATED} || $abKeys->{ABFIRST};
    
    #����������� ��������, �� ���� ����������� �����. ���������� ��������� ����������.
    #��� ����������, ����� ����������� � �������, ��� ��������� ������ ��� ���������� � ����.
    my $keys = $CACHE->getCacheContentMetadata([{REQUEST=>$abKeys->{REQUEST},CODE=>$block->{CODE}}]);
    if ($keys) {
        scalar @$keys == 1 or die "getCacheContentMetadata(): Incorrect ARRAY returned";
        $block->{CACHEKEYS} = $keys->[0] if $keys->[0];
    };
#NG::Profiler::saveTimestamp("getCacheContentMetadata for AB","pushABlock");
    
    #$keys ����������, ��� ��� ��������
    if ($keys && $abKeys->{VERSION_KEYS}) {
        #������ ���� ����������� ���� ���� ������� � ���� ����������. VERSIONS ����� ������������ � ����������� ����������.
        my $vKeys = $abKeys->{VERSION_KEYS};
        $vKeys = [$vKeys] if ref $vKeys eq "HASH";
        die "VERSION_KEYS of active block is not ARRAYREF" unless ref $vKeys eq "ARRAY";
        
        my @allCacheId = ();
        foreach my $vKey (@$vKeys) {
            $vKey->{MODULECODE} ||= $block->{MODULECODE} or die "Unable to get MODULECODE while processing VERSION_KEYS of active block";
            push @allCacheId, $vKey;
        };
        $block->{VERSIONS} = $CACHE->getKeysVersion(\@allCacheId)->[0];
        scalar(@{$block->{VERSIONS}}) == scalar(@allCacheId) or die "getKeysVersion(): Incorrect ARRAY returned";
#NG::Profiler::saveTimestamp("getKeysVersion for AB","pushABlock");
    };
    #�������� ������, ��������������� �������������� ��� ���������� �������� (USED_VERSIONS)
    if ($block->{CACHEKEYS} && $block->{CACHEKEYS}->{USED_VERSIONS}) {
        my $CUV = $block->{CACHEKEYS}->{USED_VERSIONS};
        die "Invalid USED_VERSIONS value got from cache." if ref $CUV ne "ARRAY" || scalar(@$CUV) != 2;
        die "Invalid USED_VERSIONS value got from cache. Elements are not arrays"  unless $CUV->[0] && $CUV->[1] && ref $CUV->[0] eq "ARRAY" && ref $CUV->[1] eq "ARRAY";
        die "Invalid USED_VERSIONS value got from cache. Subarray length mismatch" unless scalar(@{$CUV->[0]}) == scalar(@{$CUV->[1]});
        
        $block->{USED_VERSIONS} = $CACHE->getKeysVersion($CUV->[1],1)->[0];
        scalar(@{$block->{USED_VERSIONS}}) == scalar(@{$CUV->[1]}) or die "getKeysVersion(USED_VERSIONS): Incorrect ARRAY returned";
    };
    
    #��������, �� ������� �� ������� ��.
    if ($self->hasValidCacheContent($block)) {
        #� ���� ������� ����������. ������� �� �������. �������� ����������.
        my $content = $CACHE->getCacheContent([{REQUEST=>$abKeys->{REQUEST},CODE=>$block->{CODE}}]) or return $self->cms->error();
#NG::Profiler::saveTimestamp("getCacheContent for AB","pushABlock");
        scalar @$content == 1 or die "getCacheContent(): Incorrect ARRAY returned";
        if (defined $content->[0]) {
            #���, ������� �������
            $self->_setContentFromCache($block,$content->[0]);
            return $block->{CONTENT};
        };
warn "not found cache data: $block->{CODE} ".Dumper($block->{KEYS},$block->{CACHEKEYS});
    };
    #������� ��� ��������� �����������.
    #������� ����, ��� ����� ��������������� �� ���������� ����������� ����.
    delete $block->{CACHEKEYS};

    #������� $block->getBlockContent() ��� �������� RELATED-�������� ��� ����������� ������
    my $c = $self->getBlockContent($block);
#NG::Profiler::saveTimestamp("getBlockContent for AB","pushABlock");
    return $c if $c eq 0;
    #
    if ($c->is_exit()) {
        $CACHE->storeCacheContent([$self->_prepareCacheContent($block)]) or return $self->cms->error();
#NG::Profiler::saveTimestamp("storeCacheContent for AB","pushABlock");
    };
    return $c;
};

sub getABRelated {
    my $self = shift;
    
    my $aBlock = $self->{_ablock} or return $self->cms->error("getABRelated(): No ActiveBlock found!");
    my $abKeys = $self->_getBlockKeys($aBlock) or return $self->cms->error();
    
    unless ($abKeys->{HASRELATED}) {
        #���� �������� �����������, ����� ��. ������ �� ����� =)
        return $self->cms->error("Active Block ".$aBlock->{CODE}." does not set HASRELATED key. This can lead to floating errors on production site.");
    };
    return $aBlock->{CACHEKEYS}->{RELATED} if exists $aBlock->{CACHEKEYS} && $aBlock->{CACHEKEYS}->{RELATED};
    return $aBlock->{KEYS}->{RELATED} || return $self->cms->error("Active Block does not set value to RELATED key");
};

sub getETagSummary {
    my $self = shift;
    return "";
};

sub _getBlockObj {
    my $self = shift;
    my $block = shift;
    
    return $block->{MODULEOBJ} if $block->{MODULEOBJ};

    my $m = undef;
    $m = $block->{MODULEROW}->{module} if $block->{MODULEROW};
    
    my $cms = $self->cms();
    my $opts ={};
    $opts->{PAGEPARAMS} = $self->{_pObj}->{_pageRow};
    $opts->{PLUGINPARAMS} = $block->{PARAMS};
    if ($m) {
        $opts->{MODULEROW}= $block->{MODULEROW};
        $block->{MODULEOBJ} = $cms->getObject($m,$opts) or return $cms->error();
        return $block->{MODULEOBJ};
    };
    if ($block->{MODULECODE}) {
        $block->{MODULEOBJ} = $cms->getModuleByCode($block->{MODULECODE},$opts) or return $cms->error();
        return $block->{MODULEOBJ};
    };
    die "_getBlockObj(): No MODULECODE or MODULEROW.module ".Dumper($block);
};

sub _getBlockKeys {
    my $self = shift;
    my $block = shift;
    
    return $block->{KEYS} if exists $block->{KEYS};
    my $cms = $self->cms();
    my $bObj = $self->_getBlockObj($block) or return $cms->error();
    
    my $keys = undef;
    $keys = $bObj->getBlockKeys($block->{ACTION},$block->{PARAMS}) if ($bObj->can("getBlockKeys"));
#NG::Profiler::saveTimestamp("getBlockKeys_".ref($block->{MODULEOBJ})."_".$block->{ACTION},"getBKeys");
    if (defined $keys) {
        return $cms->defError("getBlockKeys() ����� ".$block->{CODE}." action ".$block->{ACTION}," �� ������ ��������") unless $keys;
        return $cms->error("getBlockKeys() ����� ".$block->{CODE}." action ".$block->{ACTION}." ������ �� ���") unless ref $keys eq "HASH";
    };
    $keys||={};
    $block->{KEYS} = $keys;
    return $block->{KEYS};
};

sub getBlockContent {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();

    return $block->{CONTENT} if exists $block->{CONTENT};
    
    my $bObj = $self->_getBlockObj($block) or return $cms->error();
    return $cms->error("������ ".(ref $bObj)." �� �������� ������ getBlockContent") unless $bObj->can("getBlockContent");
    
    my $keys = $self->_getBlockKeys($block) or return $cms->error();
    
    my $c = $bObj->getBlockContent($block->{ACTION}, $keys, $block->{PARAMS});
#NG::Profiler::saveTimestamp("getBlockContent_".ref($block->{MODULEOBJ})."_".$block->{ACTION},"getBContent");
    
    if (!defined $c || ($c && ref $c ne "NG::BlockContent")) {
        return $cms->error("getBlockContent() ����� ".$block->{CODE}." ������ ������������ ������� ");
    };
    $block->{CONTENT} = $c;
    return $c;
};

sub getBlockContentText {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();
    my $code = $block->{CODE};
    
    my $c = $self->getBlockContent($block);
    if (!defined $c || ($c && ref $c ne "NG::BlockContent")) {
        warn "Incorrect response for getBlockContent() block $code";
        return "[BLOCK $code RETURNS INVALID RESPONSE]";
    };
    if ($c eq 0 || $c->is_error()) {
		my $e = "";
        $e = $self->cms->getError() if $c eq 0;
        $e = $c->getError() if $c;
        warn "Block $code has error $e";
        return "[ERROR PROCESSING BLOCK $code]";
    };
    if (!$c->is_output()) {
        warn "Block $code return unsupported response";
        return "[BLOCK $code UNSUPPORTED RESPONSE]";
    };
    return $c->getOutput();
};

sub requestCacheKeys {
    my $self = shift;
    my $cms = $self->cms();
#NG::Profiler::saveTimestamp("start","requestCacheKeys");
    
    my @allCacheId = ();
    my @cachedBlocks = ();
    foreach my $block (@{$self->{_blocks}}) {
        my $keys = $self->_getBlockKeys($block) or return $cms->error();
        
        next unless exists $keys->{REQUEST};
        next if exists $block->{CACHEKEYS}; #AB with RELATED
        next if exists $block->{CONTENT};   #AB with invalid cache
        
        push @allCacheId, {REQUEST=>$keys->{REQUEST},CODE=>$block->{CODE}};
        if ($keys->{VERSION_KEYS}) {
            #������ ���� ����������� ���� ���� ������� � ���� �����������. VERSIONS ����� ������������ � ����������� ����������.
            my $vKeys = $keys->{VERSION_KEYS};
            $vKeys = [$vKeys] if ref $vKeys eq "HASH";
            die "VERSION_KEYS of block ".$block->{CODE}." is not ARRAYREF" unless ref $vKeys eq "ARRAY";
            
            my @allVersionCacheId = ();
            foreach my $vKey (@$vKeys) {
                $vKey->{MODULECODE} ||= $block->{MODULECODE} or die "Unable to get MODULECODE while processing VERSION_KEYS of block";
                push @allVersionCacheId, $vKey;
            };
            $block->{VERSIONS} = $CACHE->getKeysVersion(\@allVersionCacheId)->[0];
            if (defined $block->{VERSIONS}) {
                scalar(@{$block->{VERSIONS}}) == scalar(@allVersionCacheId) or die "getKeysVersion(): Incorrect ARRAY returned";
            };
        };
        push @cachedBlocks,$block;
    };
    
#NG::Profiler::saveTimestamp("look cache","requestCacheKeys");
    my $allMetadata = $CACHE->getCacheContentMetadata(\@allCacheId);
    if (defined $allMetadata) {
        scalar(@$allMetadata) == scalar(@cachedBlocks) or die "getCacheContentMetadata(): Incorrect ARRAY returned";
        foreach my $block (@cachedBlocks) {
            my $metadata = shift @$allMetadata;
            next unless $metadata;
            $block->{CACHEKEYS} = $metadata;
            
            #�������� ������, ��������������� �������������� ��� ���������� �������� (USED_VERSIONS)
            if ($metadata->{USED_VERSIONS}) {
                my $CUV = $metadata->{USED_VERSIONS};
                die "Invalid USED_VERSIONS value got from cache." if ref $CUV ne "ARRAY" || scalar(@$CUV) != 2;
                die "Invalid USED_VERSIONS value got from cache. Elements are not arrays"  unless $CUV->[0] && $CUV->[1] && ref $CUV->[0] eq "ARRAY" && ref $CUV->[1] eq "ARRAY";
                die "Invalid USED_VERSIONS value got from cache. Subarray length mismatch" unless scalar(@{$CUV->[0]}) == scalar(@{$CUV->[1]});
                $block->{USED_VERSIONS} = $CACHE->getKeysVersion($CUV->[1],1)->[0];
                scalar(@{$block->{USED_VERSIONS}}) == scalar(@{$CUV->[1]}) or die "getKeysVersion(USED_VERSIONS): Incorrect ARRAY returned";
            };
        };
    };
#NG::Profiler::saveTimestamp("done","requestCacheKeys");
    return 1;
};

sub hasValidCacheContent {
    my $self = shift;
    my $block = shift;

    my $cms = $self->cms();
    my $keys = $self->_getBlockKeys($block) or return $cms->error();
    my $ckeys = $block->{CACHEKEYS};
    
    return 0 unless exists $keys->{REQUEST};
    return 0 unless $ckeys && ref $ckeys;
    
    if ($ckeys->{VERSIONS} || $block->{VERSIONS}) {
        $ckeys->{VERSIONS} ||= [];
        $block->{VERSIONS} ||= [];
warn "VERSIONS length mismatch, ".$block->{CODE}.": ".scalar(@{$ckeys->{VERSIONS}}) ." != ". scalar(@{$block->{VERSIONS}}) if scalar(@{$block->{VERSIONS}}) != scalar(@{$ckeys->{VERSIONS}});
        return 0 if scalar(@{$block->{VERSIONS}}) != scalar(@{$ckeys->{VERSIONS}});
        
        my $i = -1;
        while (1) {
            $i++;
            last if !defined $ckeys->{VERSIONS}->[$i] && !defined $block->{VERSIONS}->[$i];
#warn "Compare VERSIONS : ". $ckeys->{VERSIONS}->[$i] . " and " . $block->{VERSIONS}->[$i]. " for ".$block->{CODE};
            unless ($ckeys->{VERSIONS}->[$i] && $block->{VERSIONS}->[$i]) {
                $keys->{NOCACHE} = 1; #������ �������� ������������ (�������� 0);
                return 0;
            };
            next if $ckeys->{VERSIONS}->[$i] == $block->{VERSIONS}->[$i];
            return 0;
        };
    };
    
    if ($ckeys->{USED_VERSIONS}) {
        my $CUV = $ckeys->{USED_VERSIONS}->[0]; #������ ������, ��������������� ������������� ��������
        my $BUV = $block->{USED_VERSIONS};      #������ ���������� ������
        
        my $i = -1;
        while (1) {
            $i++;
            last if !defined $CUV->[$i] && !defined $BUV->[$i];
#warn "Compare USED_VERSIONS : ". $CUV->[$i] . " and " . $BUV->[$i]. " for ".$block->{CODE};
            unless ($CUV->[$i] && $BUV->[$i]) {
                $keys->{NOCACHE} = 1; #������ �������� ������������ (�������� 0);
                return 0;
            };
            next if $CUV->[$i] == $BUV->[$i];
            return 0;
        };
    };
    
    return 0 if (exists $keys->{LM} && (!exists $ckeys->{LM} || $keys->{LM} > $ckeys->{LM}));
    return 0 if (exists $keys->{ETAG} && (!exists $ckeys->{ETAG} || $keys->{ETAG} ne $ckeys->{ETAG}));
    return 1;
};

=head
  ����� ��������������� ����������� ��������.
  �����������, ���� �� �������� ����� ���������� ������, � ��������� ����������
  ������ ����� ����� ����� ����������� ������� ��� ���� ������.
  ������: ������ "�������"
=cut
sub setBlockContent {
    my $self = shift;
    my $content = shift; #{CODE=>$codes->{$place_id},KEYS=>{REQUEST=>{place=>$rplaceId},MAXAGE=>300},CONTENT=>$cms->output($c->{$rplaceId})}
    
    die "setBlockContent(): No CODE" unless $content->{CODE};
    die "setBlockContent(): No KEYS" unless $content->{KEYS};
    die "setBlockContent(): No CONTENT" unless $content->{CONTENT};
    
    my $block = $self->{_hblocks}->{$content->{CODE}};
    die "setBlockContent(): Block ".$content->{CODE}." not found" unless $block;
    die "setBlockContent(): Block ".$content->{CODE}." has VERSIONS. This is unsupported." if $block->{VERSIONS};
    die "setBlockContent(): Block ".$content->{CODE}." has no KEYS. This is unsupported." unless $block->{KEYS};
    die "setBlockContent(): Block ".$content->{CODE}." has VERSION_KEYS. This is unsupported." if $block->{KEYS}->{VERSION_KEYS};
    
    eval "use Storable qw(freeze thaw);";
    
    if (freeze($block->{KEYS}) ne freeze($content->{KEYS})){
        eval "use Data::Dumper;";
        die "setBlockContent(): Block ".$content->{CODE}." keys mismatch: BLOCK: ".Dumper($block->{KEYS})." NEW: ".Dumper($content->{KEYS}) 
    };
    
    delete $block->{CACHEKEYS};
    $block->{CONTENT} = $content->{CONTENT};
};

sub _prepareCacheContent {
    my ($self,$block) = (shift,shift);
    
    my $c = $self->getBlockContent($block);
    
    die "Block ".$block->{CODE}." has content unsupported by cache, type ".$c->{_type} unless $c->is_output() || (($block eq $self->{_ablock}) && $c->is_exit());
    die "Block ".$block->{CODE}." has no REQUEST" unless $block->{KEYS}->{REQUEST};

    #���������� ����������
    my $metadata = {};
    
    #����������� ��������� �������� �����
    my $h = $c->headers();
    $metadata->{HEADERS} = $h if $h;
    my $hk = $c->headkeys();
    $metadata->{HEADKEYS} = $hk if $hk;
    $metadata->{TYPE} = 4 if $c->is_exit();
    
    #����������� ��������� ���������� ���������� �����
    my $UV = $block->{KEYS}->{USED_VERSIONS};
    die "Invalid USED_VERSIONS value." if $UV && (ref $UV ne "ARRAY" || scalar(@$UV) != 2);
    if ($UV && defined $UV->[0]) {
        die "Invalid USED_VERSIONS value. Elements are not arrays"  unless $UV->[0] && $UV->[1] && ref $UV->[0] eq "ARRAY" && ref $UV->[1] eq "ARRAY";
        die "Invalid USED_VERSIONS value. Subarray length mismatch" unless scalar(@{$UV->[0]}) == scalar(@{$UV->[1]});
        #��������� ���� ���� ��������
        $metadata->{USED_VERSIONS} = $UV if scalar(@{$UV->[0]});
    };
    #����������� ��������� ��� ����������� ������
    $metadata->{RELATED} = $block->{KEYS}->{RELATED} if exists $block->{KEYS}->{RELATED};
    #����������� ��������� ��� �������� �����������
    $metadata->{VERSIONS} = $block->{VERSIONS} if exists $block->{VERSIONS};
    $metadata->{ETAG}    = $block->{KEYS}->{ETAG} if exists $block->{KEYS}->{ETAG};
    $metadata->{LM}      = $block->{KEYS}->{LM}   if exists $block->{KEYS}->{LM};
    
    #�������� ������������� ������� ����� ���������� ������
    my $maxage = $MAX_CACHE_TIME;
    $maxage    = $MAX_CACHE_TIME_VERSIONS if $block->{VERSIONS};
    
    my $expire = $block->{KEYS}->{MAXAGE} || $maxage;
    $expire = $maxage if $expire > $maxage;

    return [
        {REQUEST=>$block->{KEYS}->{REQUEST},CODE=>$block->{CODE}}, #cacheId
        $metadata,          #metadata
        $c->getOutput(),    #data
        $expire             #expire
    ];
};

sub _setContentFromCache {
    my ($self, $block,$content) = (shift,shift,shift);
    
    my $type = $block->{CACHEKEYS}->{TYPE};
    $type = 1 unless defined $type;
    $type ||= 0;
    
    die "_setContentFromCache(): Unsupported content type $type" unless ($type == 1) || ($block eq $self->{_ablock});
    die "_setContentFromCache(): Unsupported content type $type" unless ($type == 1) || ($type == 4);
    
    my @args = (
        $content,
        $block->{CACHEKEYS}->{HEADERS},
    );
    push @args, $block->{CACHEKEYS}->{HEADKEYS} if $block->{CACHEKEYS}->{HEADKEYS};
    
    if ($type == 4) {
        $block->{CONTENT} = NG::BlockContent->exit(@args);
    }
    else {
        $block->{CONTENT} = NG::BlockContent->output(@args);
    };
};

sub prepareContent {
    my $self = shift;
    my $cms = $self->cms();
#NG::Profiler::saveTimestamp("start","prepareContent");
    
    #���� � ���������� �� ������ is_exit() �� ����������� ���� ���� ������ �� ����� ������.
    if  (  $self->{_ablock}
        && !exists $self->{_ablock}->{CONTENT}
        && $self->{_ablock}->{CACHEKEYS} && ($self->{_ablock}->{CACHEKEYS}->{TYPE}||1) == 4
        ) {
        #���� ������� � ���� ��������, �������� ��� ��������� ��������
        if ($self->hasValidCacheContent($self->{_ablock})) {
            my $content = $CACHE->getCacheContent([{REQUEST=>$self->{_ablock}->{KEYS}->{REQUEST},CODE=>$self->{_ablock}->{CODE}}]);
            scalar @$content == 1 or die "getCacheContent(): Incorrect ARRAY returned";
            
            if (defined $content->[0]) {
                $self->_setContentFromCache($self->{_ablock},$content->[0]);
                return $self->{_ablock}->{CONTENT};
            };
        };
        #������ �� � ���� ���������, ���� ������� �� ������.
        delete $self->{_ablock}->{CACHEKEYS};
    };
    
    my @cachedBlocks = ();
    my @allCacheId   = ();
    foreach my $block (@{$self->{_blocks}}) {
        next if $block->{CONTENT};
        if ($self->hasValidCacheContent($block)) {
            push @allCacheId, {REQUEST=>$block->{KEYS}->{REQUEST},CODE=>$block->{CODE}};
            push @cachedBlocks, $block;
            next;
        };
        delete $block->{CACHEKEYS};
    };
#NG::Profiler::saveTimestamp("checkMetadata","prepareContent");
    
    #Active block. Find it first.
    #�� �� ����� ��������� �������� � ����, ���������� �������
    if ($self->{_ablock} && !$self->{_ablock}->{CONTENT} && !$self->{_ablock}->{CACHEKEYS}) {
        my $c = $self->getBlockContent($self->{_ablock});
        return $c if $c eq 0;
        if ($c->is_exit()) {
            $CACHE->storeCacheContent([$self->_prepareCacheContent($self->{_ablock})]) or return $cms->error();
        };
        return $c if !$c->is_output();
#NG::Profiler::saveTimestamp("getABContent","prepareContent");
    };

    my $allContent = $CACHE->getCacheContent(\@allCacheId);
    if (defined $allContent) {
        scalar(@$allContent) == scalar(@cachedBlocks) or die "getCacheContent(): Incorrect ARRAY returned";
        foreach my $block (@cachedBlocks) {
            my $content = shift @$allContent;
            my $cacheId = shift @allCacheId;
            unless (defined $content) {
warn "not found cache data $cacheId : $block->{CODE} ".Dumper($block->{KEYS},$block->{CACHEKEYS});
                delete $block->{CACHEKEYS};
                next;
            };
            $self->_setContentFromCache($block,$content);
        };
    };
    #�������� ������� �� ���������� �� ����, � ��� ����� �������� ���������� �������� � ����
    if ($self->{_ablock}) {
        my $c = $self->getBlockContent($self->{_ablock});
        return $c if $c eq 0 || $c->is_error();
        if ($c->is_exit() && !$self->{_ablock}->{CACHEKEYS}) {
            $CACHE->storeCacheContent([$self->_prepareCacheContent($self->{_ablock})]) or return $cms->error();
        };
        return $c if !$c->is_output();
    };

#NG::Profiler::saveTimestamp("getCachedContent","prepareContent");
    my @newContent = ();
    #����������� ������� ���� ������, ������� �� ������� � ����.
    #��������� ����� ������� � ���.
    foreach my $block (@{$self->{_blocks}}) {
        my $blockCode = $block->{CODE};
        my $c = $self->getBlockContent($block);
        
        return $c if $c eq 0 || $c->is_error();
        unless ($c->is_output()) {
            return $c if $block->{KEYS}->{ALLOWREDIRECT} && $c->is_redirect();
            return $cms->error("Block $blockCode return unsupported response type ".$c->{_type});
        };
        
        #���, ���� ? ���������� ��������, �.�. ���� ������������ ����� $cms->addCookie() � � ����� ����������.
        my $cc = $c->cookies();
        next if $cc && scalar @{$cc}; #Skip cookies cacheing.
        next unless $block->{KEYS}->{REQUEST};      #Could be cached
        next if $block->{CACHEKEYS};                #Next if already cached
        next if $block->{KEYS}->{NOCACHE};
        
        push @newContent, $self->_prepareCacheContent($block);
    };
#NG::Profiler::saveTimestamp("getBlockContent","prepareContent");
    $CACHE->storeCacheContent(\@newContent) or return $cms->error();
#NG::Profiler::saveTimestamp("storeCacheContent","prepareContent");
    return 1;
};

sub attachTemplate {
    my $self = shift;
    my $tmplObj = shift or die "attachTemplate(): no TMPLOBJ";
    
    # �������������� ����������� ����������
    my $modules = {};
    bless $modules, "NG::BlocksController::Block";
    $modules->{_ctrl} = $self;
    $modules->{_isPlugin} = 0;
    
    my $plugins = {};
    bless $plugins, "NG::BlocksController::Block";
    $plugins->{_ctrl} = $self;
    $plugins->{_isPlugin} = 1;
    
    $tmplObj->param(
        PLUGINS => $plugins,
        MODULES => $modules,
    );
    $self->{_tmplAttached} = 1;
    return 1;
};

sub _getTmplBlockContent {
    my $self = shift;
    my $blockCode = shift;
    my $isPlugin = shift || 0;

    $self->{_tmplAttached} = 0;  #Disabled block unregistration due to possible errors from new block

    my $block = $self->{_hblocks}->{$blockCode};
    unless ($block) {
        my $e = $self->_regTmplBlock($blockCode,$isPlugin);
        return $e if $e;
        $block = $self->{_hblocks}->{$blockCode};
    };
    
    warn "Block $blockCode is not loaded from a template" if ($block->{SOURCE} ne "tmpl");
    warn "Block $blockCode requested from PLUGINS but it is MODULE" if $isPlugin &&  $block->{TYPE}!=1;
    warn "Block $blockCode requested from MODULES but it is PLUGIN" if !$isPlugin && $block->{TYPE}!=0;
    
    $self->{_usedBCodes}->{$blockCode} = 1;
    
    return $self->getBlockContentText($block);
};

sub splitRegions {
    my $self = shift;
    my $cms = $self->cms();
    my $regions = $self->{_regions} = {};
    
    foreach my $block (@{$self->{_blocks}}) {
        my $r = $block->{REGION};
        my $w = $block->{WEIGHT};
        
        if ($block->{SOURCE} eq "push") {
            $r ||= "CONTENT";
            $w ||= "0";
        }
        elsif ($block->{SOURCE} eq "neigh") {
            $r ||= "CONTENT";
        }
        elsif ($block->{SOURCE} eq "tmpl") {
            $r or next;
        }
        else {
            return $cms->error("Invalid block SOURCE");
        };
        
        return $cms->error("Block ".$block->{CODE}." has no REGION") unless $r;
        return $cms->error("Block ".$block->{CODE}." has no WEIGHT") if !defined $w || $w eq "";
        
        $regions->{$r} ||= [];
        push @{$regions->{$r}}, {
            BLOCK  => $block,
            WEIGHT => $w,
        };
    };
    1;
};

sub getRegionsContent {
    my $self = shift;
    
    my $rContent = {};
	foreach my $r (keys %{$self->{_regions}}) {
		my $c = "";
        foreach my $a (sort { $a->{WEIGHT} <=> $b->{WEIGHT}; } @{$self->{_regions}->{$r}}) {
            $c.= $self->getBlockContentText($a->{BLOCK});
        };
		$rContent->{$r} = $c;
	};
    #TODO: ������� ������� ��������� (���������� ������), �������������� ������������� �������� � �������. Tie::Hash, Tie::StdHash
    warn "Region HEAD will be overwritten" if exists $rContent->{HEAD};
    my $rHead = NG::BlocksController::RegionHead->create($self);
    $rHead->processBlocks() or return 0;
    $rContent->{HEAD} = $rHead;
    
    return $rContent;
};

sub _regTmplBlock {
    my $self = shift; 
    my $bCode = shift;
    my $isPlugin = shift;
     
    my $cms = $self->cms;
    my $dbh = $cms->dbh();
     
    my $block = $cms->getBlock($bCode);
    return "[".$cms->getError()."]" if defined $block && $block eq "0";
     
    if ($block) { 
        #Do nothing
    } 
    elsif ($isPlugin) {
        warn "Plugin $bCode not found for template '".$self->{_tmplFile}."'";
        return "[������ $bCode �� ������]";
    } 
    else { 
        #unless ($block || $isPlugin) 
        unless ($bCode =~ /^([^_]+)_(.*)$/) {
            warn "Block $bCode name is not valid for MODULES in template '".$self->{_tmplFile}."'";
            return "[������������ ��� ����� ��� ���������� MODULES: $bCode]";
        }; 
        my $code = $1;    # ��� ������
        my $action = $2;
        
        #�������� ����� �� �����, �������� ������� 
        my $moduleRow = $cms->getModuleRow("code=?",$code);
        unless ($moduleRow) {
            warn "Module $code not found while registering block $bCode";
            return $cms->getError("[������ $code �� ������ ��� ����� $bCode]");
        };
        my $blockId = $cms->db()->get_id("ng_blocks");
        warn "Registering block record for block $bCode in template '".$self->{_tmplFile}."'";
        $dbh->do("insert into ng_blocks (id, name,code, module_id, action, type) values (?,?,?,?,?,?)", undef, $blockId, 'Auto', $bCode, $moduleRow->{id}, $action, 0) or return "[������ �������� ����� $bCode: ".$DBI::errstr."]";
        
        $block = $cms->getBlock($bCode);
        return "[".$cms->getError()."]" if defined $block && $block eq "0";
    }; 
     
    return "[���� $bCode �� �������� ��������]" if $isPlugin  && $block->{TYPE} != 1;
    return "[���� $bCode �� �������� �������]"  if !$isPlugin && $block->{TYPE} != 0;
     
    warn "Block $bCode found, registering it into template '$self->{_tmplFile}'";
    $dbh->do("insert into ng_tmpl_blocks (template, block_id) values (?,?)", undef, $self->{_tmplFile}, $block->{ID}) or return $DBI::errstr;
     
    $block->{SOURCE}="tmpl";
    $self->_pushBlock($block) or return "[".$cms->getError()."]";
    return "";
}; 

sub DESTROY {
    my $self = shift;
    my $dbh = $self->dbh();

    return 1 unless $self->{_tmplFile};
    return 1 unless $self->{_tmplAttached};
    #TODO: ���������� ��������, ����� � ������ ��������������������� ����� ���������� die.
    #      ����� ����� ������ ����� ���� �� ������� �� �������, � ��� ����� ��������� ��������������.
    #      ����� ���������� ������ _inside ���� ���������� ������ �������� �������������������� �����
    #      � ��������� ��� � ���� ���������.
    unless (scalar keys %{$self->{_usedBCodes}}) {
my $aBlock = $self->{_ablock};
$aBlock = "AB ".$aBlock->{CODE} if $aBlock;
$aBlock ||= "";
warn "Layout '".$self->{_tmplFile}."' $aBlock : NG::PlugCtrl - no one module used. Possible tmpl->output() not called. Skipping remove....";
        return 1;
    };
    
    #����������� �������������� ����� � ��������������� �� �� �������
    foreach my $block (@{$self->{_blocks}}) {
        next if $self->{_usedBCodes}->{$block->{CODE}};
        
        next if $block->{SOURCE} ne "tmpl";
        next if $block->{REGION};
        next if $block->{fixed};
        next if $block->{disabled};
        
        warn "Block ".$block->{CODE}." is not used in template '".$self->{_tmplFile}."' and must be unregistered.";
        #$dbh->do("delete from ng_tmpl_blocks where template=? and  block_id=?", undef, $self->{_tmplFile}, $blockId) or warn "Error unregistering block:".$DBI::errstr;
    };
    return 1;
};


package NG::BlocksController::Block;
use strict;
our $AUTOLOAD;

sub DESTROY {
#print STDERR " NG::PlugCtrl::BLOCK DESTROYED";
    return "����������� ��� �����";
};

sub AUTOLOAD {
    my $self=shift;
    my $pkg = ref $self;
    $AUTOLOAD =~ s/$pkg\:\://;
#print STDERR " AUTOLOAD BLOCK ".$AUTOLOAD;
    local $NG::Application::blocksController = $self->{_ctrl};
    return $self->{_ctrl}->_getTmplBlockContent($AUTOLOAD, $self->{_isPlugin});
};

package NG::BlocksController::RegionHead;
use strict;
use NHtml;

sub create {
    my $class = shift;
    
    my $self = {};
    bless $self, $class;
    $self->init(@_);
    $self;
};

sub init {
    my $self = shift;
    
    $self->{_bctrl} = shift;
    $self->{_title} = undef;
    $self->{_link}  = [];
    $self->{_script}= [];
    $self->{_meta}  = [];
    
    $self->{_descr} = undef;
    $self->{_keywords} = undef;
    
    $self;
};

sub processBlocks {
    my $self = shift;
    my $bctrl = $self->{_bctrl};
    
#- �����, �������� ������� �������
#- �����, �������� �������� ������
#- �����, �������� ������� �������� ��������� �����.
    
    my ($abDescr,$abKeywords) = (0,0);
    foreach my $block (@{$bctrl->{_blocks}}) {
        next unless $block->{SOURCE} eq "push";
        $self->processBlock($block) or return 0;
        last; #Only single block can be AB
    };
    $abDescr = 1 if $self->{_descr};
    $abKeywords = 1 if $self->{_keywords};
    
    foreach my $block (@{$bctrl->{_blocks}}) {
        next unless $block->{SOURCE} eq "tmpl";
        $self->processBlock($block) or return 0;
    };
    
    foreach my $block (@{$bctrl->{_blocks}}) {
        next unless $block->{SOURCE} eq "neigh";
        $self->processBlock($block) or return 0;
    };
    
    my $pObj = $self->{_bctrl}->{_pObj};
    my $pRow = undef;
    $pRow = $pObj->getPageRow() if $pObj;

    if ($pRow) {
        $self->{_title} ||= $pRow->{title};
        if ($pRow->{description} && !$abDescr) {
            if ($self->{_descr}) {
                $self->{_descr}->{content} .= $pRow->{description}." ".$self->{_descr}->{content};
            }
            else {
                $self->_pushMeta({name=>"description",content=>$pRow->{description}}) or return 0;
            };
        };
        if ($pRow->{keywords} && !$abKeywords) {
            if ($self->{_keywords}) {
                $self->{_keywords}->{content} .= $pRow->{keywords}." ".$self->{_keywords}->{content};
            }
            else {
                $self->_pushMeta({name=>"keywords",content=>$pRow->{keywords}}) or return 0;
            };
        };
    };
    1;
};

sub _pushMeta {
    my $self = shift;
    my $meta = shift;
    
    my $cms = $self->cms();
    
    return $cms->error("Invalid hash in element of array meta: 'name' or 'http-equiv' key is missing") unless exists $meta->{name} or exists $meta->{'http-equiv'};
    return $cms->error("Invalid hash in element of array meta: key 'content' is missing") unless exists $meta->{content};
    
    if (!defined $meta->{name}) {
        #
    }
    elsif ($meta->{name} eq "keywords") {
        if ($self->{_keywords}) {
            $self->{_keywords}->{content} .= $meta->{content};
            return 1;
        }
        else {
            $self->{_keywords} = $meta;
        };
    }
    elsif ($meta->{name} eq "description") {
        if ($self->{_descr}) {
            $self->{_descr}->{content} .= " ".$meta->{content};
            return 1;
        }
        else {
            $self->{_descr} = $meta;
        };
    };
    push @{$self->{_meta}}, $meta;
    return 1;
};

sub processBlock {
    my $self = shift;
    my $block = shift;
    
    my $cms = $self->cms();
    
    my $c = $self->{_bctrl}->getBlockContent($block);
    my $hk = $c->headkeys() or return 1;
    if (exists $hk->{title}) {
        return $cms->error("Invalid value for key title in headkeys()") if (ref $hk->{title});
        return $cms->error("Invalid value for key title in headkeys()") unless defined $hk->{title};
        return $cms->error("Title already set! Unable to set title from ".$block->{CODE}) if defined $self->{_title};
        $self->{_title} = $hk->{title};
    };
    if (exists $hk->{link}) {
        return $cms->error("Invalid value for key link in headkeys()") if ref $hk->{link} ne "ARRAY";
        push @{$self->{_link}}, @{$hk->{link}};
        #foreach my $l (@{$hk->{link}}) {
        #    push @{$self->{_link}}, $l;
        #};
    };
    if (exists $hk->{script}) {
        return $cms->error("Invalid value for key link in headkeys()") if ref $hk->{script} ne "ARRAY";
        foreach my $s (@{$hk->{script}}) {
            return $cms->error("Invalid hash in element of array 'script': key 'src' or 'type' is missing") unless exists $s->{type} && exists $s->{src};
            push @{$self->{_script}}, $s;
        };
    };
    if (exists $hk->{meta}) {
        my $v = $hk->{meta};
        if (ref $v eq "HASH") {
            foreach my $key (keys %$v) {
                if ($key =~ /^-/) {
                    my $keys=$key;
                    $keys=~s/^-//;
                    $self->_pushMeta({"http-equiv"=>$keys,content=>$v->{$key}}) or return $cms->error();
                }
                else {
                    $self->_pushMeta({name=>$key,content=>$v->{$key}}) or return $cms->error();
                };
            };
        }
        elsif (ref $v eq "ARRAY") {
            foreach my $m (@$v) {
                $self->_pushMeta($m) or return $cms->error();
            };
        }
        else {
            return $cms->error("Invalid value for key meta in headkeys()");
        };
    };
    if (exists $hk->{csslist}) {
        my $v = $hk->{csslist};
        if (ref $v eq "ARRAY") {
            foreach my $css (@$v) {
                return $cms->error("Invalid value for element of array csslist") if ref $css;
                push @{$self->{_link}}, {rel=>"stylesheet",type=>"text/css",href=>$css};
            };
        }
        elsif (ref $v) {
            return $cms->error("Invalid value for csslist");
        }
        else {
            push @{$self->{_link}}, {rel=>"stylesheet",type=>"text/css",href=>$v};
        };
    };
    if (exists $hk->{jslist}) {
        my $v = $hk->{jslist};
        if (ref $v eq "ARRAY") {
            foreach my $js (@$v) {
                return $cms->error("Invalid value for element of array jslist") if ref $js;
                push @{$self->{_script}}, {type=>"text/javascript",src=>$js};
            };
        }
        elsif (ref $v) {
            return $cms->error("Invalid value for jslist");
        }
        else {
            push @{$self->{_script}}, {type=>"text/javascript",src=>$v};
        };
    };
    1;
};

sub HTML {
    my $self = shift;
    my $html = "";
    #$html.= "<title>".$self->{_title}."</title>\n" if defined $self->{_title};
    $html.= $self->LINK_HTML();
    $html.= $self->SCRIPT_HTML();
    $html.= $self->META_HTML();
    return $html;
};

sub TITLE {
    my $self = shift;
    return $self->{_title} if (defined $self->{_title});
    return "";
};

sub LINK_HTML {
    my $self = shift;
    my $html = "";
    foreach my $s (@{$self->{_link}}) {
        $html.="<link";
        foreach my $key (qw/type rel href media title/) {
            next unless exists $s->{$key};
            $html.=" ".$key."=\"".$s->{$key}."\"";
        };
        $html.="></link>";
    };
    return $html;
};

sub SCRIPT_HTML {
    my $self = shift;
    my $html = "";
    foreach my $s (@{$self->{_script}}) {
        $html.="<script";
        foreach my $key (qw/src language type charset/) {
            next unless exists $s->{$key};
            $html.=" ".$key."=\"".$s->{$key}."\"";
        };
        $html.="></script>";
    };
    return $html;
};

sub META_HTML {
    my $self = shift;
    my $html = "";
    foreach my $s (@{$self->{_meta}}) {
        $html.="<meta";
        foreach my $key (qw/name content scheme http-equiv lang dir/) {
            next unless exists $s->{$key};
            $html.=" ".$key."=\"".htmlspecialchars($s->{$key})."\"";
        };
        $html.="/>\n";
    };
    return $html;
};

sub LINK {
    my $self = shift;
    return $self->{_link};
};

sub SCRIPT {
    my $self = shift;
    return $self->{_script};
};

sub META {
    my $self = shift;
    return $self->{_meta};
};

return 1;
