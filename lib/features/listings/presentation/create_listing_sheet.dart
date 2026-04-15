import 'package:flutter/material.dart';

import '../../../models/listing.dart';
import 'create_listing_flow_result.dart';
import 'listing_form_page.dart';

Future<CreateListingFlowResult?> showCreateListingSheet(
  BuildContext context, {
  Listing? prefillListing,
  String? title,
}) {
  return showModalBottomSheet<CreateListingFlowResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.95,
        child: _CreateListingSheetBody(
          prefillListing: prefillListing,
          title: title,
        ),
      );
    },
  );
}

class _CreateListingSheetBody extends StatelessWidget {
  const _CreateListingSheetBody({
    this.prefillListing,
    this.title,
  });

  final Listing? prefillListing;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final sheetTitle =
        title ?? (prefillListing != null ? 'Relist Listing' : 'Create Listing');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 8),
          child: Row(
            children: [
              Text(
                sheetTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListingFormPage.create(
            embedded: true,
            showEmbeddedHeader: false,
            prefillListing: prefillListing,
          ),
        ),
      ],
    );
  }
}
