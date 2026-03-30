import 'package:flutter/material.dart';

import 'create_listing_flow_result.dart';
import 'listing_form_page.dart';

Future<CreateListingFlowResult?> showCreateListingSheet(BuildContext context) {
  return showModalBottomSheet<CreateListingFlowResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (sheetContext) {
      return const FractionallySizedBox(
        heightFactor: 0.95,
        child: _CreateListingSheetBody(),
      );
    },
  );
}

class _CreateListingSheetBody extends StatelessWidget {
  const _CreateListingSheetBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 8),
          child: Row(
            children: [
              Text(
                'Create Listing',
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
        const Expanded(
          child: ListingFormPage.create(
            embedded: true,
            showEmbeddedHeader: false,
          ),
        ),
      ],
    );
  }
}
