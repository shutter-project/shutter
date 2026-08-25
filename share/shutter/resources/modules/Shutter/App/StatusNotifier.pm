package Shutter::App::StatusNotifier;

use strict;
use warnings;
use Glib;
use Scalar::Util qw(blessed);
use Exporter 'import';

our @EXPORT_OK = qw(create_item);

my $active = 0;
my $object_id_sni;
my $object_id_menu;
my $dbus_conn;
my $current_menu_path;
my $menu_id_counter = 1;

# Tooltip state storage
my $tooltip_icon  = 'shutter';
my $tooltip_title = 'Shutter';
my $tooltip_text  = 'Screenshot Tool';

# Menu state storage
my $menu_revision = 1;
my %MENU_ITEMS;    # ID => MenuItem Object/HashRef
my %MENU_CHILDREN; # ID => ArrayRef of child IDs (0 acts as the root)

my $sni_xml = <<"XML";
<node>
  <interface name="org.kde.StatusNotifierItem">
    <method name="ContextMenu">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
    </method>
    <method name="Activate">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
    </method>
    <method name="SecondaryActivate">
      <arg type="i" name="x" direction="in"/>
      <arg type="i" name="y" direction="in"/>
    </method>
    <method name="Scroll">
      <arg type="i" name="delta" direction="in"/>
      <arg type="s" name="orientation" direction="in"/>
    </method>
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <signal name="NewToolTip"/>
  </interface>
</node>
XML

my $dbusmenu_xml = <<"XML";
<node>
  <interface name="com.canonical.dbusmenu">
    <method name="GetLayout">
      <arg type="i" name="parentId" direction="in"/>
      <arg type="i" name="recursionDepth" direction="in"/>
      <arg type="as" name="propertyNames" direction="in"/>
      <arg type="u" name="revision" direction="out"/>
      <arg type="(ia{sv}av)" name="item" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg type="ai" name="ids" direction="in"/>
      <arg type="as" name="propertyNames" direction="in"/>
      <arg type="a(ia{sv})" name="properties" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg type="i" name="id" direction="in"/>
      <arg type="s" name="name" direction="in"/>
      <arg type="v" name="value" direction="out"/>
    </method>
    <method name="Event">
      <arg type="i" name="id" direction="in"/>
      <arg type="s" name="eventId" direction="in"/>
      <arg type="v" name="data" direction="in"/>
      <arg type="u" name="timestamp" direction="in"/>
    </method>
    <method name="EventGroup">
      <arg type="a(isvu)" name="events" direction="in"/>
      <arg type="a(i)" name="idErrors" direction="out"/>
    </method>
    <method name="AboutToShow">
      <arg type="i" name="id" direction="in"/>
      <arg type="b" name="needUpdate" direction="out"/>
    </method>
    <property name="Version" type="u" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <signal name="LayoutUpdated">
      <arg type="u" name="revision"/>
      <arg type="i" name="parent"/>
    </signal>
    <signal name="ItemsPropertiesUpdated">
      <arg type="a(ia{sv})" name="updatedProps"/>
      <arg type="a(ia(s))" name="removedProps"/>
    </signal>
  </interface>
</node>
XML

# =========================================================================
# FACTORY METHOD
# =========================================================================

sub create_item {
    my (%props) = @_;
    my $id = $menu_id_counter++;
    return Shutter::App::StatusNotifier::MenuItem->new($id, %props);
}

# =========================================================================
# PUBLIC API
# =========================================================================

sub set_menu {
    my ($items_array_ref) = @_;

    # Reset internal storage
    %MENU_ITEMS = ();
    %MENU_CHILDREN = ( 0 => [] );

    _add_items_to_tree(0, $items_array_ref);
    _trigger_layout_update(0) if $active;
}

sub update_submenu {
    my ($parent_id, $items_array_ref) = @_;

    return unless exists $MENU_CHILDREN{$parent_id};

    $MENU_CHILDREN{$parent_id} = [];
    _add_items_to_tree($parent_id, $items_array_ref);
    _trigger_layout_update($parent_id) if $active;
}

sub set_tooltip_text {
    my ($class_or_self, $arg1, $arg2) = @_;

    if (defined $arg2) {
        $tooltip_title = $arg1;
        $tooltip_text  = $arg2;
    } else {
        $tooltip_text  = $arg1 // '';
    }

    _trigger_tooltip_update();
    return 1;
}

# =========================================================================
# INTERNAL DBUS HELPERS
# =========================================================================

sub _add_items_to_tree {
    my ($parent_id, $items) = @_;

    for my $item (@$items) {
        # Support both MenuItem objects and plain hashes
        my $is_obj = blessed($item) && $item->isa('Shutter::App::StatusNotifier::MenuItem');

        my $id       = $is_obj ? $item->id : $item->{id};
        my $children = $is_obj ? $item->children_items : $item->{children_items};

        $MENU_ITEMS{$id} = $item;
        push @{$MENU_CHILDREN{$parent_id}}, $id;

        if ($children && @$children) {
            $MENU_CHILDREN{$id} = [];
            _add_items_to_tree($id, $children);
        }
    }
}

sub _get_item_props_hash {
    my ($id) = @_;
    my $item = $MENU_ITEMS{$id};
    my %props;

    # Mark as submenu if it's the root node or contains children
    if ($id == 0 || (exists $MENU_CHILDREN{$id} && @{$MENU_CHILDREN{$id}})) {
        $props{'children-display'} = Glib::Variant->new_string('submenu');
    }

    return \%props if $id == 0 || !$item;

    my $is_obj = blessed($item) && $item->isa('Shutter::App::StatusNotifier::MenuItem');

    my $label   = $is_obj ? $item->label : $item->{label};
    my $type    = $is_obj ? $item->type : $item->{type};
    my $icon    = $is_obj ? $item->icon : $item->{icon};
    my $enabled = $is_obj ? $item->is_enabled : ($item->{enabled} // 1);
    my $visible = $is_obj ? $item->is_visible : ($item->{visible} // 1);

    $props{'label'} = Glib::Variant->new_string($label) if defined $label;
    $props{'type'}  = Glib::Variant->new_string($type)  if defined $type;

    $enabled = ($enabled && $enabled ne 'false' && $enabled ne '0') ? 1 : 0;
    $props{'enabled'} = Glib::Variant->new_boolean($enabled);

    $visible = ($visible && $visible ne 'false' && $visible ne '0') ? 1 : 0;
    $props{'visible'} = Glib::Variant->new_boolean($visible);

    $props{'icon-name'} = Glib::Variant->new_string($icon) if defined $icon && $icon ne '';

    return \%props;
}

sub _process_menu_event {
    my ($id, $event_id) = @_;
    
    # Hilfreicher Debug-Output für die Konsole:
    # warn "[DBUS-DEBUG] Event received: '$event_id' for item ID $id\n";

    if ($event_id eq 'clicked' && exists $MENU_ITEMS{$id}) {
        my $item = $MENU_ITEMS{$id};
        my $cb = (blessed($item) && $item->isa('Shutter::App::StatusNotifier::MenuItem'))
                 ? $item->callback
                 : $item->{onclick};

        if ($cb) {
            Glib::Idle->add(sub { $cb->($id); return 0; });
        }
    }
}

sub _trigger_layout_update {
    my ($parent_id) = @_;
    $parent_id //= 0;
    $menu_revision++;

    return unless $active && $dbus_conn && $current_menu_path;

    eval {
        my $sig_params = Glib::Variant->new_tuple([
            Glib::Variant->new_uint32($menu_revision),
            Glib::Variant->new_int32($parent_id)
        ]);
        $dbus_conn->emit_signal(
            undef, $current_menu_path, 'com.canonical.dbusmenu', 'LayoutUpdated', $sig_params
        );
    };
    warn "[DBUS-ERROR] LayoutUpdated failed: $@\n" if $@;
}

sub _trigger_item_property_update {
    my ($id, $prop_name, $prop_variant) = @_;

    return unless $active && $dbus_conn && $current_menu_path;

    eval {
        # Construct update array using native Perl structures.
        # Signature 'a(ia{sv})': Array of Structs (ID, Dict(String => Variant))
        my $updated_array = Glib::Variant->new('a(ia{sv})', [
            [ int($id), { $prop_name => $prop_variant } ]
        ]);

        # Array for removed properties, usually empty. Signature 'a(ias)'.
        my $removed_array = Glib::Variant->new('a(ias)', []);

        my $sig_params = Glib::Variant->new_tuple([$updated_array, $removed_array]);

        $dbus_conn->emit_signal(
            undef, $current_menu_path, 'com.canonical.dbusmenu', 'ItemsPropertiesUpdated', $sig_params
        );
    };
    warn "[DBUS-ERROR] Property update signal failed: $@\n" if $@;
}

sub _trigger_tooltip_update {
    return unless $active && $dbus_conn;

    eval {
        $dbus_conn->emit_signal(
            undef, '/StatusNotifierItem', 'org.kde.StatusNotifierItem', 'NewToolTip', undef
        );
    };
    warn "[DBUS-ERROR] NewToolTip signal failed: $@\n" if $@;
}

sub _make_item_props {
    my ($id) = @_;
    return Glib::Variant->new('a{sv}', _get_item_props_hash($id));
}

sub _make_item_struct {
    my ($id, $depth) = @_;
    my $props_var = _make_item_props($id);
    my @children_vars = ();

    if ($depth != 0 && exists $MENU_CHILDREN{$id}) {
        my $next_depth = $depth > 0 ? $depth - 1 : -1;
        for my $child_id (@{$MENU_CHILDREN{$id}}) {
            push @children_vars, _make_item_struct($child_id, $next_depth);
        }
    }

    return Glib::Variant->new_tuple([
        Glib::Variant->new_int32($id),
        $props_var,
        Glib::Variant->new('av', \@children_vars)
    ]);
}

sub init {
    my $class_or_app = shift;
    my $app = (ref($class_or_app) && $class_or_app->isa('Shutter::App')) ? $class_or_app : shift;
    my %args = @_;

    return 1 if $active;

    eval {
        my $icon_name       = $args{icon_name} || 'shutter';
        my $icon_theme_path = $args{icon_theme_path} || '';
        my $on_activate     = $args{on_activate};

        $tooltip_title = $args{title} || $args{tooltip_title} || 'Shutter';
        $tooltip_text  = $args{tooltip} || $args{tooltip_text} || 'Screenshot Tool';
        $tooltip_icon  = $icon_name;

        $dbus_conn = $app->get_dbus_connection();
        die "No D-Bus connection!" unless $dbus_conn;

        # 1. Register SNI Object
        my $sni_node = Glib::IO::DBusNodeInfo->new_for_xml($sni_xml);
        my $sni_iface = $sni_node->lookup_interface('org.kde.StatusNotifierItem');

        my $rnd_path = int(rand(10000));
        $current_menu_path = "/AppMenu_$rnd_path";

        $object_id_sni = $dbus_conn->register_object(
            '/StatusNotifierItem', $sni_iface,
            sub {
                my ($conn, $sender, $obj_path, $iface, $method, $params, $invocation) = @_;
                if ($method eq 'Activate') {
                    Glib::Idle->add(sub { $on_activate->() if $on_activate; return 0; });
                }
                eval { $invocation->return_value(Glib::Variant->new_tuple([])); };
            },
            sub {
                my ($conn, $sender, $obj_path, $iface, $prop) = @_;
                return Glib::Variant->new_string('ApplicationStatus') if $prop eq 'Category';
                return Glib::Variant->new_string('Shutter') if $prop eq 'Id' || $prop eq 'Title';
                return Glib::Variant->new_string('Active') if $prop eq 'Status';
                return Glib::Variant->new_string($icon_name) if $prop eq 'IconName';
                return Glib::Variant->new_string($icon_theme_path) if $prop eq 'IconThemePath';
                return Glib::Variant->new_boolean(0) if $prop eq 'ItemIsMenu';
                return Glib::Variant->new_int32(0) if $prop eq 'WindowId';
                return Glib::Variant->new_object_path($current_menu_path) if $prop eq 'Menu';
                if ($prop eq 'ToolTip') {
                    return Glib::Variant->new('(sa(iiay)ss)', [$tooltip_icon, [], $tooltip_title, $tooltip_text]);
                }
                return undef;
            },
            sub { return 0; }
        );

        # 2. Register DBusMenu Object
        my $menu_node = Glib::IO::DBusNodeInfo->new_for_xml($dbusmenu_xml);
        my $menu_iface = $menu_node->lookup_interface('com.canonical.dbusmenu');

        $object_id_menu = $dbus_conn->register_object(
            $current_menu_path, $menu_iface,
            sub {
                my ($conn, $sender, $obj_path, $iface, $method, $params, $invocation) = @_;

                if ($method eq 'GetLayout') {
                    eval {
                        my $parent_id = $params->get_child_value(0)->get_int32();
                        my $depth     = $params->get_child_value(1)->get_int32();
                        my $layout    = _make_item_struct($parent_id, $depth);
                        $invocation->return_value(Glib::Variant->new_tuple([
                            Glib::Variant->new_uint32($menu_revision),
                            $layout
                        ]));
                    };
                    warn "[DBUS-ERROR] GetLayout failed: $@\n" if $@;
                }
                elsif ($method eq 'GetGroupProperties') {
                    eval {
                        my $ids_var = $params->get_child_value(0);
                        my $n = $ids_var->n_children();
                        my @props_array;

                        for (my $i = 0; $i < $n; $i++) {
                            my $id = $ids_var->get_child_value($i)->get_int32();
                            if (exists $MENU_ITEMS{$id} || $id == 0) {
                                # Wir pushen hier ein reines Array-Ref mit exakt 2 Elementen [ Integer, HashRef ]
                                push @props_array, [ int($id), _get_item_props_hash($id) ];
                            }
                        }
                        $invocation->return_value(Glib::Variant->new_tuple([
                            Glib::Variant->new('a(ia{sv})', \@props_array)
                        ]));
                    };
                    warn "[DBUS-ERROR] GetGroupProperties failed: $@\n" if $@;
                }
                elsif ($method eq 'GetGroupProperties') {
                    eval {
                        my $ids_var = $params->get_child_value(0);
                        my $n = $ids_var->n_children();
                        my @props_tuples;

                        for (my $i = 0; $i < $n; $i++) {
                            my $id = $ids_var->get_child_value($i)->get_int32();
                            if (exists $MENU_ITEMS{$id} || $id == 0) {
                                push @props_tuples, Glib::Variant->new_tuple([
                                    Glib::Variant->new_int32($id),
                                    _make_item_props($id)
                                ]);
                            }
                        }
                        $invocation->return_value(Glib::Variant->new_tuple([
                            Glib::Variant->new('a(ia{sv})', \@props_tuples)
                        ]));
                    };
                    warn "[DBUS-ERROR] GetGroupProperties failed: $@\n" if $@;
                }
                elsif ($method eq 'AboutToShow') {
                    eval {
                        my $id = $params->get_child_value(0)->get_int32();
                        my $needs_update = 0;
                        my $item = $MENU_ITEMS{$id};

                        if ($item && blessed($item) && $item->can('on_about_to_show') && $item->on_about_to_show) {
                            $needs_update = $item->on_about_to_show->($id);
                        }

                        $invocation->return_value(Glib::Variant->new_tuple([
                            Glib::Variant->new_boolean($needs_update)
                        ]));
                    };
                    warn "[DBUS-ERROR] AboutToShow failed: $@\n" if $@;
                }
                elsif ($method eq 'Event') {
                    eval {
                        my $id       = $params->get_child_value(0)->get_int32();
                        my $event_id = $params->get_child_value(1)->get_string();

                        _process_menu_event($id, $event_id);

                        $invocation->return_value(Glib::Variant->new_tuple([]));
                    };
                    warn "[DBUS-ERROR] Event failed: $@\n" if $@;
                }
                elsif ($method eq 'EventGroup') {
                    eval {
                        my $events_var = $params->get_child_value(0);
                        my $n = $events_var->n_children();

                        for (my $i = 0; $i < $n; $i++) {
                            my $event_struct = $events_var->get_child_value($i);
                            my $id       = $event_struct->get_child_value(0)->get_int32();
                            my $event_id = $event_struct->get_child_value(1)->get_string();

                            _process_menu_event($id, $event_id);
                        }

                        # EventGroup erwartet ein Array von Fehler-IDs als Rückgabe (leer = keine Fehler)
                        $invocation->return_value(Glib::Variant->new_tuple([
                            Glib::Variant->new('a(i)', [])
                        ]));
                    };
                    warn "[DBUS-ERROR] EventGroup failed: $@\n" if $@;
                }
                else {
                    eval { $invocation->return_value(Glib::Variant->new_tuple([])); };
                }
            },
            sub {
                my ($conn, $sender, $obj_path, $iface, $prop) = @_;
                return Glib::Variant->new_uint32(3) if $prop eq 'Version';
                return Glib::Variant->new_string('ltr') if $prop eq 'TextDirection';
                return Glib::Variant->new_string('normal') if $prop eq 'Status';
                return undef;
            },
            sub { return 0; }
        );

        # 3. Register at Watcher
        $dbus_conn->call(
            'org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher',
            'org.kde.StatusNotifierWatcher', 'RegisterStatusNotifierItem',
            Glib::Variant->new('(s)', ['/StatusNotifierItem']), undef, 'none', -1, undef,
            sub {
                my ($c, $res) = @_;
                eval { $c->call_finish($res); };
            }
        );

        $active = 1;
    };

    if ($@) {
        warn "[DBUS-ERROR] SNI GDBus initialization error: $@\n";
        $active = 0;
    }
    return $active;
}

# =========================================================================
# CLASS: MenuItem
# =========================================================================

package Shutter::App::StatusNotifier::MenuItem;

sub new {
    my ($class, $id, %props) = @_;

    my $self = {
        id             => $id,
        label          => $props{label},
        icon           => $props{icon},
        enabled        => defined $props{enabled} ? $props{enabled} : 1,
        visible        => defined $props{visible} ? $props{visible} : 1,
        type           => $props{type},
        onclick        => $props{onclick} || $props{on_click},
        children_items => $props{children_items} || [],
    };

    return bless $self, $class;
}

# --- GETTERS ---
sub id             { return shift->{id}; }
sub label          { return shift->{label}; }
sub icon           { return shift->{icon}; }
sub is_enabled     { return shift->{enabled}; }
sub is_visible     { return shift->{visible}; }
sub type           { return shift->{type}; }
sub callback       { return shift->{onclick}; }
sub children_items { return shift->{children_items}; }

# --- SETTERS ---
# Updates immediately trigger targeted D-Bus property changes.

sub set_enabled {
    my ($self, $value) = @_;
    $self->{enabled} = $value;
    my $bool_variant = Glib::Variant->new_boolean($value ? 1 : 0);
    Shutter::App::StatusNotifier::_trigger_item_property_update($self->{id}, 'enabled', $bool_variant);
}

sub set_visible {
    my ($self, $value) = @_;
    $self->{visible} = $value;
    my $bool_variant = Glib::Variant->new_boolean($value ? 1 : 0);
    Shutter::App::StatusNotifier::_trigger_item_property_update($self->{id}, 'visible', $bool_variant);
}

sub set_label {
    my ($self, $value) = @_;
    $self->{label} = $value;
    my $str_variant = Glib::Variant->new_string($value // '');
    Shutter::App::StatusNotifier::_trigger_item_property_update($self->{id}, 'label', $str_variant);
}

sub set_icon {
    my ($self, $value) = @_;
    $self->{icon} = $value;
    my $str_variant = Glib::Variant->new_string($value // '');
    Shutter::App::StatusNotifier::_trigger_item_property_update($self->{id}, 'icon-name', $str_variant);
}

sub set_children {
    my ($self, $children_array_ref) = @_;
    $self->{children_items} = $children_array_ref || [];

    # Structural changes require rebuilding the specific submenu branch
    Shutter::App::StatusNotifier::update_submenu($self->{id}, $self->{children_items});
}

1;
