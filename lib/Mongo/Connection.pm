package Mongo::Connection;

use Any::Moose;

has host => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'localhost',
);

has port => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
    default  => 27017,
);

has _server => (
    is       => 'ro',
    isa      => 'Str',
    lazy     => 1,
    builder  => '_build__server',
);

has auto_reconnect => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
    default  => 0,
);

has auto_connect => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
    default  => 1,
);

has _database_class => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'Mongo::Database',
);

has _cursor_class => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'Mongo::Cursor',
);

has _oid_class => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'Mongo::OID',
);

sub _build__server {
    my ($self) = @_;
    my ($host, $port) = map { $self->$_ } qw/host port/;
    return "${host}:${port}";
}

sub BUILD {
    my ($self) = @_;
    eval "use ${_}" # no Any::Moose::load_class becase the namespaces already have symbols from the xs bootstrap
        for map { $self->$_ } qw/_database_class _cursor_class _oid_class/;
    $self->_build_xs;
    $self->connect if $self->auto_connect;
}

sub connect {
    my ($self) = @_;
    $self->_connect;
    return;
}

sub find_one {
    my ($self, $ns, $query) = @_;
    $query ||= {};
    return $self->_find_one($ns, $query);
}

sub query {
    my ($self, $ns, $query, $limit, $skip) = @_;
    $query ||= {};
    $limit ||= 0;
    $skip  ||= 0;
    return $self->_query($ns, $query, $limit, $skip);
}

sub insert {
    my ($self, $ns, $object) = @_;
    confess 'not a hash reference' unless ref $object eq 'HASH';
    my %copy = %{ $object }; # a shallow copy is good enough. we won't modify anything deep down in the structure.
    $copy{_id} = $self->_oid_class->new unless exists $copy{id};
    $self->_insert($ns, \%copy);
    return $copy{_id};
}

sub update {
    my ($self, $ns, $query, $object, $upsert) = @_;
    $upsert = 0 unless defined $upsert;
    $self->_update($ns, $query, $object, $upsert);
    return;
}

sub remove {
    my ($self, $ns, $query) = @_;
    $self->_remove($ns, $query, 0);
    return;
}

{
    my %direction_map = (
        ascending  => 1,
        descending => -1,
    );

    sub ensure_index {
        my ($self, $ns, $keys, $direction) = @_;
        $direction ||= 'ascending';

        my %keys;
        if (ref $keys eq 'ARRAY') {
            %keys = map { ($_ => $direction) } @{ $keys };
        }
        elsif (ref $keys eq 'HASH') {
            %keys = %{ $keys };
        }
        else {
            confess 'expected hash or array reference for keys';
        }

        $self->_ensure_index($ns, { map {
            my $dir = $keys{$_};
            confess "unknown direction '${dir}'"
                unless exists $direction_map{$dir};
            ($_ => $direction_map{$dir})
        } keys %keys });
        return;
    }
}

sub database_names {
    my ($self) = @_;
    my $ret = $self->get_database('admin')->run_command({ listDatabases => 1 });
    return map { $_->{name} } @{ $ret->{databases} };
}

sub get_database {
    my ($self, $database_name) = @_;
    return $self->_database_class->new(
        _connection => $self,
        name        => $database_name,
    );
}

sub authenticate {
    my ($self, @args) = @_;
    return $self->_authenticate(@args);
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
