#!/usr/bin/perl 

=head1 NAME

precluster.pl -- a script to precluster sequences based on a self-blast using a -m8 blast output

=head1 DESCRIPTION

precluster.pl [options] [-f seqfile.fasta] [-q qualfile] [-b selfblastm8output]

=head2 Note

If you want to pipe in the m8 output directly from the blast, give a hyphen instead of a filename for the selfblastm8outputfile.

=head2 options: 

=over 5

=item -f

fast file

=item -q

quality file

=item -b

selfblast result in m8 format

=item -o

the output file directory. It will be created if it does not exist. The default: creates a directory called tmp/ in the current directory.

=item -e

the evalue cutoff [Default: 1e-10]

=item -l

the mininum alignment length [optional]

=item -p

the mininum percent identity [optional]

=item -v

verbose output, and we really mean verbose.

=back

=head1 VERSION

1e-10

=head1 AUTHOR

Lukas Mueller <lam87@cornell.edu>

=cut

use strict;
use Getopt::Std;
use Bio::Index::Fasta;
use Bio::Index::Qual;
use Bio::Seq;
use Bio::SeqIO;

use vars qw( $opt_e $opt_o $opt_v $opt_l $opt_p $opt_f $opt_q $opt_b );

getopts('e:o:vl:p:f:q:b:');

if (!$opt_f && !$opt_b) { 

    print <<HELP;

    precluster.pl [-elpvo ] -f <fastafile> [ -q <qualfile> ] -b <blastm8file>

	-e: evalue cutoff [default 1e-10]
	-l: minimum alignment length [optional]
        -p: minimum percent identity [optional]
	-o: output directory [default current directory]
	-v: verbose

     Hint: enter a dash "-" for the blastm8file if you want to 
           pipe blast output directly into precluster.pl.

    Thanks! Have a good day!

HELP

    exit();
}

if (!$opt_e) { 
    $opt_e = 1e-10;
    print STDERR "Using default evalue cutoff of $opt_e.\n";
}

if (!$opt_o) { 
    $opt_o = "tmp/";
    print STDERR "Using default output dir of $opt_o.\n";
}

if (!$opt_p) { 
    $opt_p = 0;
}

if (!$opt_l) { 
    $opt_l = 0;
}

my $seqfile = $opt_f || die("ARGUMENT ERROR: None -f <fasta_file> was supplied.\n\n");
my $qualfile = $opt_q;
my $blastm8file = $opt_b || die("ARGUMENT ERROR: None -b <blast_m8_result> was supplied.\n\n");

print STDERR "Indexing file $seqfile...\n";
my $inx = Bio::Index::Fasta->new(-filename => $seqfile.".INDEX",
				 -write_flag => 1);
$inx->make_index($seqfile);

my $inxq = undef;
if ($qualfile) { 
    print STDERR "Indexing file $qualfile...\n";
    $inxq = Bio::Index::Qual->new(-filename => $qualfile.".INDEX",
				     -write_flag => 1);
    $inxq->make_index($qualfile);
}

my $set = CXGN::Cluster::ClusterSet->new();

$set->set_debug($opt_v);

my $F;

if ($blastm8file eq "-") {
    print STDERR "Note: Expecting blast m8 on STDIN...\n";
}



open ($F, "<$blastm8file") || die "Can't open file \"$blastm8file\". ";

print STDERR "Parsing m8 blast report... this may take a while...\n";


while (<$F>) { 
    chomp;
    my ( $query_id,
	 $subject_id,
	 $percent_identity,
	 $alignment_len,
	 $mismatches,
	 $gap_openings,
	 $q_start,
	 $q_end,	 
	 $s_start,
	 $s_end,
	 $evalue,
	 $bitscore,
	 $score,
	 $description)  = split/\t/;

        if ( ($evalue < $opt_e) && ($percent_identity>$opt_p) && ($alignment_len>$opt_l)) { 
	if ($opt_v) { 
	    print STDERR "Adding match $query_id, $subject_id, $evalue, $percent_identity, $alignment_len\n";
	}
	
	$set->add_match($query_id, $subject_id);
    } 
    elsif ($opt_v) {
	print STDERR "Skipping match $query_id, $subject_id, $evalue, $percent_identity, $alignment_len\n";
    }
}
if ($blastm8file ne "-" ) { close ($F); }

# generate a couple of multi-fasta file for each cluster,
# one with the sequence info, one with quality info
# use bioperl indexed files for fast access.
#
if (! -d $opt_o) { mkdir $opt_o; }

my $cluster_count = 0;

my $singleton_out = Bio::SeqIO->new('-format'=>'Fasta', 
				    '-file' => ">".$opt_o."/singletons.seq");

my $singleton_qual = "";

if ($qualfile) { 
    $singleton_qual = Bio::SeqIO->new('-format'=>'qual',
				      '-file' => ">".$opt_o."/singletons.qual");
}
my $SUMMARY;
open ($SUMMARY, ">".$opt_o."/summary.txt") || die "Can't open summary file for writing";

foreach my $c ($set->get_clusters()) { 
    my ($seqout, $qualout) = (undef, undef);
    print "Cluster: ".$c->get_unique_key()." (".$c->get_size().")\n";
    if ($c->get_size()<=1) { 
	$seqout = $singleton_out;
	$qualout = $singleton_qual;
    }
    else { 
	$seqout = Bio::SeqIO->new('-format'=>'Fasta', 
				  '-file' => ">".$opt_o."/cluster-".$cluster_count.".seq");
	$qualout = undef;
	if ($qualfile) { 
	    $qualout = Bio::SeqIO->new('-format'=>'qual',
				       '-file'=> ">".$opt_o."/cluster-".$cluster_count.".qual");
	}
    }
    foreach my $id ($c->get_members()) {
	
	# print to the summary file. Three columns: the cluster id, the cluster_type (S=singleton, C=contig), and 
        # the id of the member sequence.
	#
	my $cluster_type = "C";
	if ($c->get_size()==1) { $cluster_type="S"; } 
	print $SUMMARY "cluster-$cluster_count\t$cluster_type\t$id\n";

	# print out the the sequence files
	#
	my $seq_obj = $inx->get_Seq_by_id($id);
	my $qual_obj = undef;
	if ($qualfile) {  
	    $qual_obj = $inxq ->get_Seq_by_id($id); 
	    if ($opt_v) { print STDERR "QUAL: ".$qual_obj->qual()."\n"; }
	}
	$seqout->write_seq($seq_obj);
	if ($qualfile) { $qualout->write_seq($qual_obj); }
    }
    
    # cleanup
    #
    if ($c->get_size()>1) { 
	$seqout->close();    
	if ($qualfile) { $qualout->close(); }
    }
    $cluster_count++;
}

$singleton_out->close();
if ($qualfile) { $singleton_qual->close(); }
close($SUMMARY);

=head1 PACKAGES

Currently, the following packages are also contained in this script:

=over 5

=item o

CXGN::Cluster::Object

=item o

CXGN::Cluster::ClusterSet

=item o

CXGN::Cluster::Precluster

=back

=head1 PACKAGE CXGN::Cluster::Object

Parent class for cluster objects.

=cut

package CXGN::Cluster::Object;

=head2 new()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub new { 
    my $class = shift;
    my $args = {};
    my $self = bless $args, $class;
    return $self;
}

=head2 get_debug()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_debug {
  my $self=shift;
  return $self->{debug};

}

=head2 set_debug()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub set_debug {
  my $self=shift;
  $self->{debug}=shift;
}

sub debug { 
    my $self = shift;
    my $message = shift;
    if ($self->get_debug()) { 
	print STDERR "$message";
    }
}


=head1 PACKAGE CXGN::Cluster::ClusterSet

CXGN::Cluster::ClusterSet - a package to manage sets of preclusters

=cut

package CXGN::Cluster::ClusterSet;

use base qw( CXGN::Cluster::Object );

=head2 new()

 Usage:
 Desc:         Constructor
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub new { 
    my $class = shift;
    my $self = $class -> SUPER::new(@_);
    $self->reset_unique_key();
    keys(%{$self->{key_hash}})=100000;
    return $self;
}

=head2 add_match()

 Usage:
 Desc:
 Ret:
 Args:         two ids representing the match.
 Side Effects:
 Example:

=cut


sub add_match { 
    my $self = shift;
    my $query_id = shift;
    my $subject_id = shift;
    my $c1 = $self->get_cluster($query_id);
    my $c2 = $self->get_cluster($subject_id);
    if ( ($c1 && $c2) && ($c1 == $c2) ) { 
	$self->debug(" [ ignoring both in ".$c1->get_unique_key()."]");
	# do nothing, because both have already been added
	# to the same precluster
    }
    elsif ( ($c1 && $c2) && ($c1 != $c2) ) { 
	$self->debug("IDs already in distinct clusters. Combining...\n");
	# we have a problem because the two have 
	# already been assigned to distinct sub-clusters.
	# we need to pull the clusters together.
	$self->debug("Before combining: " 
		     .$c1->get_unique_key().":".$c1->get_size().
		     " ".$c2->get_unique_key().":".$c2->get_size()."\n");
	$c1->combine($c2);
	$self->debug("After combining: "
		     .$c1->get_unique_key().":".$c1->get_size()."\n");
    }
    elsif ($c1 && !$c2) { 
	$self->debug("query $query_id already in cluster [".$c1->get_unique_key()."], adding $subject_id\n");
	$c1->add_member($subject_id);	    
	$self->debug("Now containing ".$c1->get_size()." members.\n");
    }
    elsif (!$c1 && $c2) { 
	$self->debug("subject $subject_id already in cluster [".$c2->get_unique_key()."], adding $query_id\n");
	$c2->add_member($query_id);
    }
    else { 
	$self->debug("creating new cluster...\n");
	# there is no cluster yet...
	# generate a new cluster
	my $new = CXGN::Cluster::Precluster->new($self);
	$self->add_cluster($new);
	$new->add_member($query_id);
	$new->add_member($subject_id);
	$new->debug($self->get_debug());
    }
}

=head2 add_cluster()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub add_cluster { 
    my $self = shift;
    my $cluster = shift;
#    my $unique_key = $cluster->get_unique_key();
    $self->add_key_hash($cluster);
}

sub add_key_hash { 
    my $self = shift;
    my $cluster = shift;
    my $unique_key = $cluster->get_unique_key();
    $self->{key_hash}{$unique_key}=$cluster;
}

=head2 remove_cluster()

 Usage:
 Desc:          removes the cluster from the cluster_set.
                the entry in the cluster hash table is deleted.
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub remove_cluster { 
    my $self = shift;
    my $cluster = shift;
    $self->debug("Deleting cluster ".$cluster->get_unique_key()."...\n");
    delete($self->{key_hash}{$cluster->get_unique_key()});
}

=head2 get_clusters()

 Usage:
 Desc:         gets all clusters as list of cluster objects.
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_clusters { 
    my $self = shift;
    return values(%{$self->{key_hash}});
}

=head2 add_id()

 Usage:
 Desc:         add a seq id to the cluster hash for fast 
               cluster retrieval using a seq id.
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub add_id { 
    my $self = shift;
    my $cluster = shift;
    my $id = shift;
    if (!$id || !$cluster) { die "need cluster object and id"; }
    $self->{id_map}{$id}=$cluster;
}

=head2 get_cluster()

 Usage:
 Desc:         gets the cluster that contains the sequence with id $id.
               see also add_id().
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_cluster { 
    my $self = shift;
    my $id = shift;
    if (!$id) { die "get_cluster_with_id: need an id!\n"; }
    return $self->{id_map}{$id};
}

=head2 generate_unique_key()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub generate_unique_key {
    my $self=shift;
    return ($self->{unique_key})++;
}

=head2 reset_unique_key()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub reset_unique_key {
    my $self=shift;
    $self->{unique_key}=0;
}


=head1 PACKAGE CXGN::Cluster::Precluster

A class that deals with preclusters.

=head1 FUNCTIONS

=cut

package CXGN::Cluster::Precluster;

use base qw ( CXGN::Cluster::Object );

sub new { 
    my $class = shift;
    my $self = $class -> SUPER::new(@_);
    my $cluster_set = shift;
    if (!$cluster_set) { 
	die "CXGN::Cluster::Precluster::new()- need cluster set"; 
    }
    $self->set_cluster_set($cluster_set);
    $self->set_unique_key($self->get_cluster_set()->generate_unique_key());
    #print STDERR "Generated cluster with unique key = ".$self->get_unique_key()."\n";
    return $self;
}

=head2 add_member()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub add_member { 
    my $self = shift;
    my $id = shift;

    $self->{members}{$id}++;
    $self->get_cluster_set()->add_id($self, $id);
}

=head2 get_members()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_members {
    my $self = shift;
    return keys(%{$self->{members}});
}

=head2 get_members_fasta()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_members_fasta {
    my $self= shift;
    my $inx = shift;
    my $out = shift;
    foreach my $id ($self->get_members()) { 
	my $seq = $inx -> fetch($id);
	$out->write_seq($seq);
    }
}


=head2 get_cluster_set()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_cluster_set {
  my $self=shift;
  return $self->{cluster_set};

}

=head2 set_cluster_set()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub set_cluster_set {
  my $self=shift;
  $self->{cluster_set}=shift;
}

=head2 get_unique_key()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_unique_key {
  my $self=shift;
  return $self->{unique_key};
}

=head2 set_unique_key()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub set_unique_key {
  my $self=shift;
  $self->{unique_key}=shift;
}

=head2 get_size()

 Usage:       
 Desc:
 Ret:          returns the size of the cluster,
               in terms of members.
 Args:
 Side Effects:
 Example:

=cut

sub get_size {
    my $self = shift;
    return scalar( keys(%{$self->{members}})); 
}



sub combine { 
    my $self = shift;
    my $other = shift;
    
    my @other_members = $other->get_members();
    foreach my $o (@other_members) { 
	$self->add_member($o);
    }
    $self->get_cluster_set()->remove_cluster($other);
}





