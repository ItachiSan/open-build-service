package BSRepServer::BuildInfo;

use strict;
use warnings;

use Data::Dumper;

use BSConfiguration;
use BSRPC ':https';
use BSUtil;
use BSXML;
use Build;

use BSRepServer;
use BSRepServer::Checker;
use BSSched::BuildJob;		# expandkiwipath

sub new {
  my $class = shift;
  my $self  = {@_};

  my $gctx = {
    arch        => $self->{arch},
    reporoot    => "$BSConfig::bsdir/build",
    #extrepodir  => "$BSConfig::bsdir/repos",
    #extrepodb   => "$BSConfig::bsdir/db/published",
    remoteproxy => $BSConfig::proxy,
    remoteprojs => {},
  };

  my $ctx = BSRepServer::Checker->new($gctx, project => $self->{projid}, repository => $self->{repoid});

  $self->{gctx} = $gctx;
  $self->{ctx} = $ctx;

  bless($self, $class);

  # get projpack information for generating remotemap
  $self->get_projpack_via_rpc();
  $self->{proj} = $self->{projpack}->{'project'}->[0];
  $self->{repo} = $self->{proj}->{'repository'}->[0];

  $gctx->{'projpacks'}->{$self->{'projid'}} = $self->{'proj'};

  # generate initial remotemap
  $self->{remotemap} = $gctx->{'remoteprojs'} = { map {$_->{'project'} => $_} @{$self->{projpack}->{'remotemap'} || []} };

  # create pdata (package data) if needed and verify
  my $pdata = $self->{pdata};
  if (!$pdata) {
    $pdata = $self->{proj}->{'package'}->[0];
    die("no such package\n") unless $pdata && $pdata->{'name'} eq $self->{packid};
    die("$pdata->{'error'}\n") if $pdata->{'error'};
    $pdata->{'buildenv'} = getbuildenv($self->{projid}, $self->{repoid}, $self->{arch}, $self->{packid}, $pdata->{'srcmd5'}) if $pdata->{'hasbuildenv'};
  }
  die("$pdata->{'buildenv'}->{'error'}\n") if $pdata->{'buildenv'} && $pdata->{'buildenv'}->{'error'};
  $self->{pdata} = $pdata;
  if ($self->{packid}) {
    # take debuginfo from package if we have it
    $pdata->{'debuginfo'} = $self->{proj}->{'package'}->[0]->{'debuginfo'} if $self->{packid};
    # fixup packages so that it is a hash (needed for kiwi products)
    $self->{'proj'}->{'package'} = { $self->{packid} => $pdata };
  }
  $self->{info} = $pdata->{'info'}->[0];
  die("bad info\n") unless $self->{info} && $self->{info}->{'repository'} eq $self->{repoid};

  # find build type
  my $buildtype = $pdata->{'buildtype'} || Build::recipe2buildtype($self->{info}->{'file'}) || 'spec';
  $pdata->{'buildtype'} = $buildtype;

  if ($buildtype eq 'kiwi') {
    my $remotemap = $self->{remotemap};
    my $info = $self->{'info'};
    if (@{$info->{'path'} || []}) {
      # fill in all remotemap entries we need
      my @args = map {"project=$_->{'project'}"} grep {$_->{'project'} ne '_obsrepositories'} @{$info->{'path'}};
      if (@args) {
        push @args, "partition=$BSConfig::partition" if $BSConfig::partition;
        my $pp = BSRPC::rpc("$BSConfig::srcserver/getprojpack", $BSXML::projpack, 'withremotemap', 'nopackages', @args);
        $remotemap->{$_->{'project'}} = $_ for @{$pp->{'remotemap'} || []};
      }
    }
    if ($self->{info}->{'imagetype'} && $self->{info}->{'imagetype'}->[0] eq 'product') {
      # sigh. Need to get the project kind of the involved projects
      my @prpsearchpath = map {"$_->{'project'}/$_->{'repository'}"} @{$self->{repo}->{'path'} || []};
      my @aprps = BSSched::BuildJob::expandkiwipath($self->{info}, \@prpsearchpath);
      my %prjkind;
      for my $aprp (@aprps) {
	my ($aprojid) = split('/', $aprp, 2);
	next if $aprojid eq $self->{'projid'} || $remotemap->{$aprojid};
	$prjkind{$aprojid} = undef;
      }
      if (%prjkind) {
	print "fetching project kind for ".keys(%prjkind)." projects\n";
	my $projpack = BSRPC::rpc("$BSConfig::srcserver/getprojpack", $BSXML::projpack, 'nopackages', 'noremote', 'ignoredisable', map {"project=$_"} sort(keys %prjkind));
	for my $p (@{$projpack->{'project'} || []}) {
	  $gctx->{'projpacks'}->{$p->{'name'}}->{'kind'} = $p->{'kind'};
	}
      }
    }
  }

  return $self;
}

sub getbuildenv {
  my ($projid, $repoid, $arch, $packid, $srcmd5) = @_;
  my $res = BSRPC::rpc({
    'uri' => "$BSConfig::srcserver/source/$projid/$packid",
  }, $BSXML::dir, "rev=$srcmd5");
  my %entries = map {$_->{'name'} => $_} @{$res->{'entry'} || []};
  my $bifile = "_buildenv.$repoid.$arch";
  $bifile = '_buildenv' unless $entries{$bifile};
  die("srcserver is confused about the buildenv\n") unless $entries{$bifile};
  return BSRPC::rpc({
    'uri' => "$BSConfig::srcserver/source/$projid/$packid/$bifile",
  }, $BSXML::buildinfo, "rev=$srcmd5");
}

sub get_projpack_via_rpc {
  my ($self) = @_;
  
  # prepare args for rpc call
  my @args = ("project=$self->{projid}", "repository=$self->{repoid}", "arch=$self->{arch}", "parseremote=1");
  if (defined($self->{packid})) {
    push @args, "package=$self->{packid}";
  } else {
    push @args, "nopackages";
  }
  push @args, "partition=$BSConfig::partition" if $BSConfig::partition;

  # fetch projpack information via rpc
  if (!$self->{pdata}) {
    $self->{projpack} = BSRPC::rpc("$BSConfig::srcserver/getprojpack", $BSXML::projpack, 'withsrcmd5', 'withdeps', 'withrepos', 'expandedrepos', 'withremotemap', 'ignoredisable', @args);
    die("404 no such project/package/repository\n") unless $self->{projpack}->{'project'};
  } else {
    $self->{projpack} = BSRPC::rpc("$BSConfig::srcserver/getprojpack", $BSXML::projpack, 'withrepos', 'expandedrepos', 'withremotemap', @args);
    die("404 no such project/repository\n") unless $self->{projpack}->{'project'};
  }

  # verify projpack
  my $proj = $self->{projpack}->{'project'}->[0];
  die("no such project\n") unless $proj && $proj->{'name'} eq $self->{projid};
  my $repo = $proj->{'repository'}->[0];
  die("no such repository\n") unless $repo && $repo->{'name'} eq $self->{repoid};
}

sub addpreinstallimg {
  my ($ctx, $binfo, $preimghdrmd5s) = @_;
  return unless $preimghdrmd5s && %$preimghdrmd5s;
  my $projid = $binfo->{'project'};
  my $repoid = $binfo->{'repository'};
  my $packid= $binfo->{'package'};
  my $arch = $binfo->{'arch'};
  my @prpas = map {$_->name() . "/$arch"} $ctx->{'pool'}->repos();
  my $bestimgn = 2; 
  my $bestimg;

  for my $prpa (@prpas) {
    my $images = BSRepServer::getpreinstallimages($prpa);
    next unless $images;
    for my $img (@$images) {
     next if @{$img->{'hdrmd5s'} || []} < $bestimgn;
     next unless $img->{'sizek'} && $img->{'hdrmd5'};
     next if grep {!$preimghdrmd5s->{$_}} @{$img->{'hdrmd5s'} || []}; 
     next if $prpa eq "$projid/$repoid/$arch" && $packid && $img->{'package'} eq $packid;
     $img->{'prpa'} = $prpa;
     $bestimg = $img;
     $bestimgn = @{$img->{'hdrmd5s'} || []}; 
   }
  }
  return unless $bestimg;
  my $pi = {'package' => $bestimg->{'package'}, 'filename' => "_preinstallimage.$bestimg->{'hdrmd5'}", 'binary' => $bestimg->{'bins'}, 'hdrmd5' => $bestimg->{'hdrmd5'}};
  ($pi->{'project'}, $pi->{'repository'}) = split('/', $bestimg->{'prpa'}, 3);
  my $rprp = "$pi->{'project'}/$pi->{'repository'}";
  my $rprp_ext = $rprp;
  $rprp_ext =~ s/:/:\//g;
  my $rurl = BSRepServer::get_downloadurl($rprp, $rprp_ext);
  $pi->{'url'} = $rurl if $rurl;
  $binfo->{'preinstallimage'} = $pi;
}

sub addurltopath {
  my ($ctx, $binfo) = @_;
  my $remoteprojs = $ctx->{'gctx'}->{'remoteprojs'};
  for my $r (@{$binfo->{'path'}}) {
    delete $r->{'server'};
    next if $remoteprojs->{$r->{'project'}};	# what to do with those?
    my $rprp = "$r->{'project'}/$r->{'repository'}";
    my $rprp_ext = $rprp;
    $rprp_ext =~ s/:/:\//g;
    my $rurl = BSRepServer::get_downloadurl($rprp, $rprp_ext);
    $r->{'url'} = $rurl if $rurl;
  }
}

sub getbuildinfo {
  my ($self) = @_;

  my $pdata = $self->{pdata};
  my $info = $self->{info};
  my $ctx = $self->{'ctx'};
  my $packid = $self->{'packid'};
  my $repo = $self->{'repo'};

  my $buildtype = $pdata->{'buildtype'};
  my @prpsearchpath = map {"$_->{'project'}/$_->{'repository'}"} @{$repo->{'path'} || []};
  $ctx->{'prpsearchpath'} = \@prpsearchpath;
  $repo->{'path'} = [] if $buildtype eq 'kiwi' && @{$repo->{'path'} || []} < 2;		# HACK

  $ctx->setup();
  my $bconf = $ctx->{'conf'};
  $bconf->{'type'} = $buildtype if $buildtype;

  $ctx->preparepool($info->{'name'}, $pdata->{'ldepfile'});
  my $binfo;

  eval {
    $binfo = $ctx->buildinfo($packid, $pdata, $info);
  };
  if ($@) {
    $binfo = BSSched::BuildJob::create_jobdata($ctx, $packid, $pdata, $info, $ctx->{'subpacks'}->{$info->{'name'}});
    $binfo->{'error'} = $@;
    chomp($binfo->{'error'});
  } else {
    delete $binfo->{$_} for qw{job needed constraintsmd5 prjconfconstraint nounchanged revtime reason nodbgpkgs nosrcpkgs};
    delete $binfo->{'reason'};
  }
  $binfo->{'specfile'} = $binfo->{'file'} if $binfo->{'file'};	# compat
  if ($binfo->{'syspath'}) {
    $binfo->{'syspath'} = [] if grep {$_->{'project'} eq '_obsrepositories'} @{$info->{'path'} || []};
    unshift @{$binfo->{'path'}}, @{delete $binfo->{'syspath'}};
  }
  addurltopath($ctx, $binfo);
  # never use the subpacks from the full tree
  $binfo->{'subpack'} = $info->{'subpacks'} if $info->{'subpacks'};
  $binfo->{'subpack'} = [ sort @{$binfo->{'subpack'} } ] if $binfo->{'subpack'};
  $binfo->{'downloadurl'} = $BSConfig::repodownload if defined $BSConfig::repodownload;
  $binfo->{'debuginfo'} ||= 0;	# XXX: why?
  #print Dumper($binfo);
  my %preimghdrmd5s = map {delete($_->{'preimghdrmd5'}) => 1} grep {$_->{'preimghdrmd5'}} @{$binfo->{'bdep'}};
  addpreinstallimg($ctx, $binfo, \%preimghdrmd5s) unless $self->{'internal'};
  return ($binfo, $BSXML::buildinfo);
}

1;
