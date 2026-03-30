enum CreateListingNextAction {
  done,
  viewListing,
}

class CreateListingFlowResult {
  const CreateListingFlowResult._({
    required this.action,
    this.listingId,
  });

  const CreateListingFlowResult.done()
      : this._(action: CreateListingNextAction.done);

  const CreateListingFlowResult.viewListing(String listingId)
      : this._(
          action: CreateListingNextAction.viewListing,
          listingId: listingId,
        );

  final CreateListingNextAction action;
  final String? listingId;
}
