import 'listing.dart';

enum TransactionRole { lent, borrowed }

class UserTransaction {
  const UserTransaction({
    required this.offerId,
    required this.listingId,
    required this.title,
    required this.category,
    required this.listingType,
    required this.role,
    required this.counterpartyId,
    required this.acceptedAt,
  });

  final String offerId;
  final String listingId;
  final String title;
  final String category;
  final ListingType listingType;
  final TransactionRole role;
  final String counterpartyId;
  final DateTime? acceptedAt;
}
