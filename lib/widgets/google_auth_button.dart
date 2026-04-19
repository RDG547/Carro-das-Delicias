import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/loading_manager.dart';

class GoogleAuthButton extends StatelessWidget {
  final LoadingManager loadingManager;
  final String loadingKey;
  final String text;
  final VoidCallback? onPressed;

  const GoogleAuthButton({
    super.key,
    required this.loadingManager,
    required this.loadingKey,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingBuilder(
      loadingManager: loadingManager,
      loadingKey: loadingKey,
      builder: (context, isLoading) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey.shade300),
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/google_g.svg',
                        width: 22,
                        height: 22,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
