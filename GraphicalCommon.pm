

#my $balloon = $mw->Balloon();

sub addListBox {
	my $parentElement = shift;
	my $labelName = shift;
	my $CQ_Field = shift;
	my $necessityText = shift;
	my $labelDescription = shift;
	my $listToInsert = shift;
	
	my $newElement = $parentElement->JComboBox(-label => $labelName, -labelWidth => 15, -labelPack=>[-side=>'left'], -textvariable => \$bugDescription{$CQ_Field}, -choices => $listToInsert, -browsecmd => [\&analyseListboxes])->pack(-fill => 'x', -side => 'top', -anchor => 'center'); # -> pack(-fill => 'both', -expand => 1)
	$newElement->setSelected($bugDescription{$CQ_Field}) if $bugDescription{$CQ_Field};
	#$balloon->attach($newElement, -msg => "<$necessityText> $labelDescription");
	push(@mandatoryFields, {Text => $labelName, CQ_Field => $CQ_Field}) if $necessityText eq 'Mandatory';
	
	return $newElement;
}

sub addDescriptionField {
	my $container = shift;
	my $text = shift;
	my $CQ_Field = shift;
	my $necessityText = shift;
	my $description = shift;
	
	my %item;
	$item{selection} = \$bugDescription{$CQ_Field};
	$item{DescriptionPanel} = $container->Frame() -> pack(-side => 'top', -fill => 'both', -expand => 1);
	$item{DescriptionPanel}->Label(-text => $text, -width => 15 )->pack( -side => 'left' );
	$item{Text} = $item{DescriptionPanel}->Scrolled("Text", -scrollbars => 'osoe') -> pack( -side => 'top', -fill => 'both');
	$item{Text}->bind( '<FocusOut>' => sub { $item{selection} = $item{Text}->Contents(); } );
}

sub addSearchableListBox {
	my $parentElement = shift;
	my $labelName = shift;
	my $CQ_Field = shift;
	my $necessityText = shift;
	my $labelDescription = shift;
	my $completeList = shift;

	my %completeList;
	if (ref $completeList eq "ARRAY") {
		foreach my $item (@$completeList) {
			$completeList{$item} = $item;
		}
	}
	elsif(ref $completeList eq "HASH") { %completeList = %$completeList; }
	
	my %item;
	my @list;

	my $oldValue = $bugDescription{$CQ_Field};
	$item{searchActivated} = 0;
	$item{selectedList} = \@list;
	$item{selection} = \$bugDescription{$CQ_Field};
	$item{mainFrame} = $parentElement->Frame()->pack(-side => 'top', -fill => 'x');
	$item{mainFrame}->Label(-text => $labelName, -width => 15 )->pack(-side => 'left');
	$item{searchButton} = $item{mainFrame}->Button(-text => 'Search', -command => sub { manageSearchBox(\%item) }, -state => 'disabled')->pack( -side => 'right' );
	$item{listbox} = $item{mainFrame}->JComboBox(-choices => $item{selectedList}, -textvariable => $item{selection}, -state => 'disabled')->pack(-fill => 'x', -side => 'left', -expand => 1);
	$item{searchFrame} = $item{mainFrame}->Frame();
	$item{searchDescription} = $item{searchFrame}->Label(-textvariable => \$item{searchText})->pack(-side => 'left');
	$item{searchFrame}->Entry(-validate => 'all', -textvariable => \$item{search}, -width => 15, -validatecommand => sub { my $search = shift; search(\%item, $search); return 1; } )->pack(-side => 'right');

	changeList(\%item, \%completeList, $oldValue) if %completeList;
	#$balloon->attach($item{listbox}, -msg => "<$necessityText> $labelDescription");
	#push(@mandatoryFields, {Text => $labelName, CQ_Field => $CQ_Field});

	return \%item;
}

sub manageSearchBox {
	my $searchListbox = shift;
	
	$searchListbox->{searchActivated} = ($searchListbox->{searchActivated}+1)%2;
	if($searchListbox->{searchActivated}) {
		DEBUG "Search activated";
		$searchListbox->{searchButton}->configure(-text => 'X');
		$searchListbox->{searchFrame}->pack(-fill => 'x', -side => 'right', -anchor => 'center');
		#$balloon->attach($searchListbox->{searchButton}, -msg => 'Cancel search');
	}
	else {
		DEBUG "Search deactivated";
		$searchListbox->{search} = '';
		$searchListbox->{searchButton}->configure(-text => 'Search');
		$searchListbox->{searchFrame}->packForget();
		#$balloon->attach($searchListbox->{searchButton}, -msg => 'Perform a search on left list');
	}
}

sub changeList {
	my $item = shift;
	my $completeList = shift;
	my $selection = shift;
	
	$item->{completeList} = $completeList;

	my @list = sort keys %$completeList;
	@{$item->{selectedList}} = @list;
	$item->{searchButton}->configure(-state => (scalar(@list))?'normal':'disabled');
	$item->{listbox}->configure(-state => (scalar(@list))?'normal':'disabled');
	
	DEBUG "Trying to set default value \"$selection\"" and $item->{listbox}->setSelected($selection) if $selection;
}

sub search {	
	my $searchListbox = shift;
	my $search = shift;
	
	DEBUG "Search request is : \"$search\"";
	my @tmpList;
	my %completeList = %{$searchListbox->{completeList}};
	my @resultsText = ("Hereafter are results remainings:");
	my $old_selection = ${$searchListbox->{selection}};
	foreach my $item (keys %completeList) {
		next unless (not $search or $search eq '' or $item =~ /$search/i or $completeList{$item} =~ /$search/i);
		push (@tmpList, $item);
		push (@resultsText, " => $item --- $completeList{$item}");
	}
	my $nbrOfResults = scalar(@tmpList);
	@{$searchListbox->{selectedList}} = sort @tmpList;
	${$searchListbox->{selection}} = $old_selection if $old_selection;
	${$searchListbox->{selection}} = $tmpList[0] if $nbrOfResults == 1;

	#$balloon->attach($searchListbox->{searchDescription}, -msg => join("\n", @resultsText));
	$searchListbox->{listbox}->configure(-state => $nbrOfResults ? 'normal' : 'disabled');
	$searchListbox->{searchText} = ($nbrOfResults ? ($nbrOfResults == 1 ? "1 result" : $nbrOfResults.' results' ) : 'No results');
	return 1;
}

1;