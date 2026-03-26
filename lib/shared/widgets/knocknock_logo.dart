import 'package:flutter/material.dart';

class KnocknockLogo extends StatelessWidget {
  const KnocknockLogo({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: size,
            height: size,
            color: Theme.of(context).colorScheme.primaryContainer,
            alignment: Alignment.center,
            child: Icon(
              Icons.handshake_outlined,
              size: size * 0.6,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          );
        },
      ),
    );
  }
}

class KnocknockWordmark extends StatelessWidget {
  const KnocknockWordmark({super.key, this.width = 180, this.height = 42});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/wordmark.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return Text(
          'Knocknock',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        );
      },
    );
  }
}
